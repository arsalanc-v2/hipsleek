#include <stdio.h>
// star_fields
struct node {
  int x;
  struct node* next;
};

/*@
ll<n> == self=null & n=0
  or self::node<_,q>*q::ll<n-1>
  inv n>=0;
*/

int foo(struct node* q)
/*@
  requires q::ll<n>
  ensures q::ll<n> & res=n;
*/
{
  //printf("q = %i\n",q);
  //struct node* tmp = q;
  //printf("tmp = %i\n",tmp);
  if (q) return 1+foo(q->next);
  else {
    //printf("rec q = %i\n",q);
    return 0;
  };
}

/*
 null --> !res
 !null --> res


Below is wrong...

boolean bool_of_node___(node param)[]
static 

(None,[]): case{ECase:
         param != null->
(None,[]): EAssume: 4,:(emp)*(!(res))( FLOW __norm)
         param = null->
(None,[]): EAssume: 3,:(emp)*(res)( FLOW __norm)
}
*/


int main() 
/*@
 requires true
 ensures res=0;
*/
{
  struct node* p;
  p=0;
  int r=foo(p);
  //printf("r = %i\n",r);
  return r;
}

