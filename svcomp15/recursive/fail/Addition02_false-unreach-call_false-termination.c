extern void __VERIFIER_error() __attribute__ ((__noreturn__));

/*
 * Recursive implementation integer addition.
 * 
 * Author: Matthias Heizmann
 * Date: 2013-07-13
 * 
 */

extern int __VERIFIER_nondet_int(void);

int addition(int m, int n)
/*@
  infer[@pre_n,@post_n]
  requires true ensures true;
 */
 {
    if (n == 0) {
        return m;
    }
    if (n > 0) {
        return addition(m+1, n-1);
    }
    if (n < 0) {
        return addition(m-1, n+1);
    }
     return 0;
}


int main() {
    int m = __VERIFIER_nondet_int();
    int n = __VERIFIER_nondet_int();
    int result = addition(m,n);
    if (result == m - n) {
        return 0;
    } else {
        ERROR: __VERIFIER_error();
    }
}

