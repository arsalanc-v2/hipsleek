// pass-by-value
//#include <stdlib.h>

struct pair {
  int x;
  int y;
};

void* malloc(int size) __attribute__ ((noreturn))
/*@
  case {
    size <= 0 -> requires true ensures res = null;
    size >  0 -> requires true ensures res != null;
  }
*/;

void hoo(struct pair *q)
/*@
 requires q::pair<a,b>
 ensures q::pair<a,b>;
*/
{
  q = malloc(sizeof(struct pair));
}

int main() 
{
  return 1;
}

