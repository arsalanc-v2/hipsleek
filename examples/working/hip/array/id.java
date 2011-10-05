/**
 * inverting the indices
 * 
 */

relation dom(int[] a, int low, int high) == 
	(dom(a,low-1,high) | dom(a,low,high+1)).

relation bnd(int[] a, int i, int j, int low, int high) == 
 	(i > j | i<=j & forall ( k : (k < i | k > j | low <= a[k] <= high))).

relation idexc(int[] a, int[] b, int i, int j) == 
	forall(k : (i<=k & k<=j | a[k] = b[k])).

// relation bnd(int[] a, int i, int j, int low, int high) == 
// 	bnd(a,i-1,j+1,low,high).

// bnd(a,i,j,low,high) & i<=s & b<=j  => bnd(a,s,b,low,high)
void invert(ref int[] a, int i, int j
            , int low, int high
            ) 
    /*
	requires dom(a,i,j) 
       & bnd(a,i,j,low,high) 
	ensures dom(a',i,j) //'
       & bnd(a',i,j,low,high) 
    ;
    */
    /*
	requires 
    //[low,high]
     dom(a,i,j) & bnd(a,i,j,low,high) 
    case {
      i>=j -> ensures a'=a; //'
      i<j -> ensures dom(a',i,j) //'
             & bnd(a',i,j,low,high) ;//'
    }
    */
    requires dom(a,i,j)
    ensures dom(a',i,j);
/*
ERROR: File "id.java", line 43, col 14 : Post condition cannot be derived by the system. 
*/
    requires bnd(a,i,j,low,high)
    case {
      i>=j -> ensures bnd(a',i,j,low,high)  & a'=a ; //'
      i<j -> ensures 
              //dom(a',i,j) & //'
             idexc(a,a',i,j) &
             bnd(a',i,j,low,high) ;//'
    }

{
	if (i<j) {
        swap(a,i,j);
        //assume false;
        invert(a,i+1,j-1
               ,low,high
        );
    }
}


void swap (ref int[] a, int i, int j)
                         /*
    requires [t,k] dom(a,t,k) & t <= i &  i <= k & t <= j & j <= k 
            //& bnd(a,t,k,low,high) 
    	ensures dom(a',t,k) & a'[i]=a[j] & a'[j]=a[i] & 
       forall(m: m=i | m=j | a'[m]=a[m] ) //'
            //& bnd(a',t,k,low,high)//'
       ;
                         */

    requires [t,k] dom(a,t,k) & t <= i &  i <= k & t <= j & j <= k 
	ensures dom(a',t,k);//'
    requires true
    ensures (exists b:update_array(a,i,a[j],b) & update_array(b,j,a[i],a')); //'
    //ensures a'[i]=a[j] & a'[j]=a[i] & forall(m: m=i | m=j | a'[m]=a[m] ); //'

{
    int t = a[i];
    a[i] = a[j];
    a[j] = t;
}
