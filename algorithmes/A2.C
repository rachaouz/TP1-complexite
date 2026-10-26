#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define REP 1

int est_premier(long long n)
{
    long long i;
    if (n < 2) return 0;
    for (i = 2; i <= n / 2; i++)         
        if (n % i == 0) return 0;
    return 1;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        printf("Usage : %s fichier_entree.txt\n", argv[0]);
        return 1;
    }

    FILE *fin = fopen(argv[1], "r");
    if (fin == NULL) {
        printf("Erreur : impossible d'ouvrir %s\n", argv[1]);
        return 1;
    }

    long long n;
    double total = 0.0;                          
    printf("%-15s %-10s %s\n", "N", "Premier ?", "T (secondes)");

    while (fscanf(fin, "%lld", &n) == 1) {
        int res = 0;
        int r;

        clock_t debut = clock();                 
        for (r = 0; r < REP; r++)
            res = est_premier(n);
        clock_t fin_t = clock();                 

        double temps = ((double)(fin_t - debut) / CLOCKS_PER_SEC) / REP;
        total += temps;                          

        printf("%-15lld %-10s %.6f\n", n, res ? "OUI" : "NON", temps);
    }

    printf("\nTemps total : %.6f secondes\n", total);

    fclose(fin);
    return 0;
}