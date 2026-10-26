
param([string]$Dossier = "resultats")
Set-Location $PSScriptRoot

$algos  = "A1","A2","A3","A4"
$jeux   = "Random100.txt","Random1000.txt","Test-1.txt","Test-2.txt","Test-3.txt"
$exclus = "mesures.csv","mesures_detail.csv"

# 1. Fichiers de resultats a fusionner (du plus ancien au plus recent)
$fichiers = Get-ChildItem $Dossier -Filter *.csv |
    Where-Object { $_.Name -notmatch '_detail\.csv$' -and $_.Name -notmatch '\.bak' -and ($exclus -notcontains $_.Name) -and $_.Length -gt 0 } |
    Sort-Object LastWriteTime

# 2. Une ligne retenue par combinaison : un OK remplace un non-OK, le plus recent OK gagne
$choisi = @{}
foreach ($fi in $fichiers) {
    foreach ($l in (Get-Content $fi.FullName | Select-Object -Skip 1)) {
        if (-not $l.Trim()) { continue }
        $c = $l.Split(';')
        if ($c.Count -lt 7) { continue }
        $cle = "$($c[0])|$($c[1])"
        $ok  = ($c[6] -eq "OK")
        $ancien = $choisi[$cle]
        if ((-not $ancien) -or $ok -or (-not $ancien.Ok)) {
            $choisi[$cle] = [pscustomobject]@{ Ligne = $l; Ok = $ok; Source = $fi.FullName }
        }
    }
}

# 3. Assemblage dans l'ordre jeu de donnees puis algorithme
$csv = @("Algorithme;Jeu_de_donnees;Nombre_de_valeurs;Nombre_de_premiers;REP;Temps_total_s;Statut")
$det = @("Algorithme;Jeu_de_donnees;N;Premier;Temps_par_nombre_s")
$problemes = @()
foreach ($j in $jeux) {
    foreach ($a in $algos) {
        $r = $choisi["$a|$j"]
        if (-not $r) {
            $csv += "$a;$j;;;;;ABSENT"
            $problemes += "$a / $j : ABSENT (aucun resultat trouve)"
            continue
        }
        $csv += $r.Ligne
        if (-not $r.Ok) { $problemes += "$a / $j : " + $r.Ligne.Split(';')[6] }
        $dp = $r.Source -replace '\.csv$','_detail.csv'
        if (Test-Path $dp) {
            $det += Get-Content $dp | Select-Object -Skip 1 | Where-Object { $_.StartsWith("$a;$j;", [StringComparison]::OrdinalIgnoreCase) }
        }
    }
}

# 4. Sauvegarde des anciens fichiers finaux puis ecriture
$sortie  = Join-Path $Dossier "mesures.csv"
$sortieD = Join-Path $Dossier "mesures_detail.csv"
foreach ($p in @($sortie, $sortieD)) {
    if ((Test-Path $p) -and (Get-Item $p).Length -gt 0) {
        Copy-Item $p ($p + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    }
}
$csv | Set-Content -Path $sortie  -Encoding UTF8
$det | Set-Content -Path $sortieD -Encoding UTF8

# 5. Verification
$nbOk = @($csv | Select-Object -Skip 1 | Where-Object { $_.EndsWith(";OK") }).Count
Write-Host ""
Write-Host "Fichiers fusionnes :"
$fichiers | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host ""
Write-Host "$nbOk / 20 combinaisons OK -> $sortie"
Write-Host "Lignes de detail : $($det.Count - 1) -> $sortieD"
if ($problemes.Count -gt 0) {
    Write-Host ""
    Write-Host "A verifier :"
    $problemes | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""
Get-Content $sortie