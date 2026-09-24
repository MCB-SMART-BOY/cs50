import check50
import check50.c

@check50.check()
def exists():
    """caesar.c exists."""
    check50.exists("caesar.c")

@check50.check(exists)
def compiles():
    """caesar.c compiles."""
    check50.c.compile("caesar.c", lcs50=True)

@check50.check(compiles)
def encrypts_a_as_b():
    """encrypts "a" as "b" using 1 as key"""
    check50.run("./caesar 1").stdin("a").stdout("[Cc]iphertext: *b\n", "ciphertext: b\n").exit(0)
