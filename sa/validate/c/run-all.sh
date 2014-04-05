HIP=../../../hip
echo "ll-trav.ss"
$HIP ll-trav.c -validate ../o/ll-trav.cp | grep Validate
echo "ll-trav-1.ss: ll with at least one node"
$HIP ll-trav-1.c -validate ../o/ll-trav-1.cp | grep Validate
#echo "sll-reverse"
#$HIP sll-reverse.c -validate ../o/sll-reverse.cp | grep Validate
echo "zip_paper_eq"
$HIP zip_paper_eq.c -validate ../o/zip_paper_eq.cp | grep Validate
echo "sll+head"
$HIP check-sll-head.c -validate ../o/check-sll-head.cp | grep Validate
echo "check-sll-head"
$HIP check-sll-head.c -validate ../o/check-sll-head.cp | grep Validate
echo "skip2-list"
$HIP skip2-list.c  --pred-en-dangling --pred-en-equiv -validate ../o/skip2-list.cp | grep Validate
echo "skip3-list"
$HIP skip3-list.c  --pred-en-dangling --pred-en-equiv -validate ../o/skip3-list.cp | grep Validate
echo "check-sorted recursion"
$HIP check-sorted.c --sa-en-pure-field -validate ../o/check-sorted.cp | grep Validate
echo "check-sorted with while"
#$HIP check-sorted-while.c --sa-en-pure-field -validate ../o/check-sorted.cp | grep Validate
echo "sll-insertsort"
$HIP sll-insertsort.c -validate ../o/sll-insertsort.cp | grep Validate
echo "CSll"
$HIP cll.c  --pred-en-dangling -validate ../o/cll.cp | grep Validate
echo "check-csll"
$HIP check-cll.c  --pred-en-dangling -validate ../o/check-cll.cp | grep Validate
echo " 0/1 SLLs"
$HIP sll-01-slls.c  --pred-en-dangling -validate o/sll-01-slls.cp | grep Validate
echo "sll2dll"
$HIP sll-dll.c  --pred-en-dangling --pred-en-equiv -validate ../o/sll-dll.cp | grep Validate
echo "check-dll"
$HIP check-dll.c -tp z3  --pred-en-dangling -validate ../o/check-dll.cp | grep Validate
echo "bt-search-2."
$HIP bt-search-2.c -tp z3 --pred-unify-post -validate  ../o/bt-search-2.cp | grep Validate
echo "tll"
$HIP tll.c  --pred-en-dangling -tp z3 --pred-en-equiv -validate ../o/tll.cp | grep Validate
echo "rose-tree"
$HIP rose-tree-1.c --pred-en-dangling  --pred-en-equiv -validate ../o/rose-tree-1.cp | grep Validate
echo "check mcf"
$HIP check-mcf.c --pred-en-dangling -validate ../o/check-mcf.cp | grep Validate
echo "tll-parent.c"
$HIP tll-parent.c -tp z3 --pred-en-dangling --pred-en-equiv -validate ../o/tll-parent.cp | grep Validate
#echo "ll-back.ss"
#$HIP ll-back.ss
#sa-dangling
echo "dll-app: to improvo/rectify segmentation"
$HIP dll-append_paper.c -tp z3 --pred-en-dangling -validate ../o/dll-append_paper.cp | grep Validate
#pred-disj-unify
#echo "ll-trav-1.ss --pred-disj-unify"
#$HIP ll-trav-1.c --pred-disj-unify -validate ../o/ll-trav-1-unify.cp | grep Validate

#pred-en-split
echo "cyc-lseg"
#$HIP cyc-lseg.c  -validate ../o/cyc-lseg.cp --pred-en-split | grep Validate
echo "zip_paper_eq"
$HIP zip_paper_eq.c  --sa-ext -validate ../o/zip_paper_eq-split.cp --pred-en-split | grep Validate

#pred-unify-post
echo "cyc-tree (search)"
$HIP cyc-tree-1.c --pred-unify-post -validate ../o/cyc-tree-1.cp | grep Validate
echo "bt-search-2.ss"
$HIP bt-search-2.c --pred-unify-post -validate  ../o/bt-search-2.cp | grep Validate
#sa-dnc

#--pred-en-equiv
