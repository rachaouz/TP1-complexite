param(
    [string[]]$Algos = @("A1","A2","A3","A4"),
    [string[]]$Fichiers = @("Random100.txt","Random1000.txt","Test-1.txt","Test-2.txt","test-3.txt"),
    [string]$Sortie = "resultats\mesures.csv",
    [int]$TimeoutSec = 1800
)
$racine = $PSScriptRoot
Set-Location $racine
$src = Join-Path $racine "algorithmes"
$inv = [Globalization.CultureInfo]::InvariantCulture
New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $racine $Sortie)) | Out-Null

# 1. Compilation sans optimisation, en forcant le langage C
foreach ($a in $Algos) {
    gcc -O0 -x c (Join-Path $src "$a.C") -o (Join-Path $src "$a.exe")
    if ($LASTEXITCODE -ne 0) { throw "Erreur de compilation : $a" }
}

# 2. Localisation des jeux de donnees (aucune copie, aucune modification)
$chemins = @{}
foreach ($f in $Fichiers) {
    $p = Get-ChildItem -Path $racine -Recurse -File -Filter $f | Select-Object -First 1
    if (-not $p) { throw "Jeu de donnees introuvable sous $racine : $f" }
    $chemins[$f] = $p.FullName
    Write-Host "Jeu de donnees : $($p.FullName)"
}

# 3. Execution et lecture des sorties
$res = @()
$detail = @()
$sig = @{}
foreach ($f in $Fichiers) {
    $attendu = [regex]::Matches((Get-Content $chemins[$f] -Raw), '-?\d+').Count
    foreach ($a in $Algos) {
        Write-Host "$a sur $f ..."
        $tmp  = Join-Path $env:TEMP "sortie_$a.txt"
        $proc = Start-Process -FilePath (Join-Path $src "$a.exe") -ArgumentList "`"$($chemins[$f])`"" -RedirectStandardOutput $tmp -NoNewWindow -PassThru
        $null = $proc.Handle
        if ($proc.WaitForExit($TimeoutSec * 1000)) { $code = $proc.ExitCode } else { $proc.Kill(); $proc.WaitForExit(); $code = -999 }
        $out  = @(Get-Content $tmp -ErrorAction SilentlyContinue)
        $rows = @($out | Select-String -Pattern '^\s*(-?\d+)\s+(OUI|NON)\s+([\d.]+)\s*$')
        $tot  = $out | Select-String -Pattern 'Temps total : ([\d.]+) secondes'
        $rep  = (Select-String -Path (Join-Path $src "$a.C") -Pattern '#define\s+REP\s+(\d+)').Matches[0].Groups[1].Value
        if ($code -eq 0) {
            foreach ($m in $rows) {
                $g = $m.Matches[0].Groups
                $detail += "$a;$f;$($g[1].Value);$($g[2].Value);$($g[3].Value.Replace('.',','))"
            }
        }
        $nb   = $rows.Count
        $np   = @($rows | Where-Object { $_.Matches[0].Groups[2].Value -eq 'OUI' }).Count
        $temps = ""
        $statut = "OK"
        if ($code -eq -999)  { $statut = "TIMEOUT" }
        elseif ($code -ne 0) { $statut = "ERREUR_EXECUTION" }
        elseif (-not $tot)   { $statut = "TEMPS_ABSENT" }
        else {
            $t = [double]::Parse($tot.Matches[0].Groups[1].Value, $inv)
            $temps = $t.ToString("F6", $inv).Replace('.', ',')
            if ($nb -ne $attendu) { $statut = "NB_VALEURS_INATTENDU($nb/$attendu)" }
        }
        $sig["$a|$f"] = ($rows | ForEach-Object { $_.Matches[0].Groups[1].Value + $_.Matches[0].Groups[2].Value }) -join ','
        $res += [pscustomobject]@{ A=$a; F=$f; NB=$nb; NP=$np; REP=$rep; T=$temps; S=$statut }
        Write-Host "   -> $statut $temps"
    }
}

# 4. Coherence : les algorithmes OK doivent donner les memes OUI/NON
foreach ($f in $Fichiers) {
    $liste = @($res | Where-Object { $_.F -eq $f -and $_.S -eq "OK" })
    if ($liste.Count -gt 1) {
        $ref = $sig["$($liste[0].A)|$f"]
        foreach ($r in $liste) { if ($sig["$($r.A)|$f"] -ne $ref) { $r.S = "DIVERGENCE_RESULTATS" } }
    }
}

# 5. Sauvegarde des anciens CSV puis ecriture
$detailPath = $Sortie -replace '\.csv$','_detail.csv'
foreach ($p in @($Sortie, $detailPath)) {
    if ((Test-Path $p) -and (Get-Item $p).Length -gt 0) {
        $bak = "$p.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
        Copy-Item $p $bak
        Write-Host "Ancien fichier sauvegarde : $bak"
    }
}
$csv = @("Algorithme;Jeu_de_donnees;Nombre_de_valeurs;Nombre_de_premiers;REP;Temps_total_s;Statut")
$csv += $res | ForEach-Object { "$($_.A);$($_.F);$($_.NB);$($_.NP);$($_.REP);$($_.T);$($_.S)" }
$csv | Set-Content -Path $Sortie -Encoding UTF8
(@("Algorithme;Jeu_de_donnees;N;Premier;Temps_par_nombre_s") + $detail) | Set-Content -Path $detailPath -Encoding UTF8

# 6. Verification
$nbOk = @($res | Where-Object { $_.S -eq "OK" }).Count
Write-Host "`n$nbOk / $($Algos.Count * $Fichiers.Count) combinaisons OK -> $Sortie (detail : $detailPath)"
$res | Where-Object { $_.S -ne "OK" } | ForEach-Object { Write-Host "PROBLEME : $($_.A) / $($_.F) : $($_.S)" }
