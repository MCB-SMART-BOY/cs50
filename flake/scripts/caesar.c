#include <cs50.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, string argv[])
{
    if (argc != 2)
    {
        return 1;
    }
    for (int i = 0; argv[1][i] != '\0'; i++)
    {
        if (!isdigit((unsigned char) argv[1][i]))
        {
            return 1;
        }
    }
    int key = atoi(argv[1]) % 26;
    string plaintext = get_string("plaintext:  ");
    printf("ciphertext: ");
    for (int i = 0; plaintext[i] != '\0'; i++)
    {
        char c = plaintext[i];
        if (islower((unsigned char) c))
        {
            printf("%c", 'a' + (c - 'a' + key) % 26);
        }
        else if (isupper((unsigned char) c))
        {
            printf("%c", 'A' + (c - 'A' + key) % 26);
        }
        else
        {
            printf("%c", c);
        }
    }
    printf("\n");
    return 0;
}
