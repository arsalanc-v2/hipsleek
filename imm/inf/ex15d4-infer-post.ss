data cell{
 int fst;
}

//relation P(int x, int y).

  int foo2(cell c)
    infer [@term]
  requires c::cell<yyy>
    ensures c::cell<5> & res=5;
{
  int x = c.fst;
  if (x>0) c.fst = 5;
  return x;
}