// addr-of operator
// how come we don't use pass-by-copy here?
// pass-by-copy only for struct?
// how about struct*, do we use pass-by-copy?
int foo(int** q)
/*@
  requires q::int_star_star<r>*r::int_star<a>
  ensures q::int_star_star<r>*r::int_star<a+1> & res=a+1;
*/
{
  int* r = *q;
  *r = *r+1;
  return *r;
};

struct pair {
  int x;
  int y;
};

int main()
/*@
  requires true
  ensures res=3;
*/
{
  int x;
  x=5;
  int* r = &x;
  x=2;
  int t=foo(&r);
  int k=x+1;
  struct pair p;
  struct pair* pp;
  pp = &p;
  return x;
}


