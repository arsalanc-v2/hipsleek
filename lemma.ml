open Globals
open Wrapper
open Gen
open Others
open Label_only

module AS = Astsimp
module C  = Cast
module IF = Iformula
module IP = Ipure
module CF = Cformula
module CP = Cpure
module MCP = Mcpure
module H  = Hashtbl
module I  = Iast
module SC = Sleekcore
module LP = Lemproving
module SAO = Saout
module FP = Fixpoint

let infer_shapes = ref (fun (iprog: I.prog_decl) (cprog: C.prog_decl) (proc_name: ident)
  (hp_constrs: CF.hprel list) (sel_hp_rels: CP.spec_var list) (sel_post_hp_rels: CP.spec_var list)
  (hp_rel_unkmap: ((CP.spec_var * int list) * CP.xpure_view) list)
  (unk_hpargs: (CP.spec_var * CP.spec_var list) list)
  (link_hpargs: (int list * (Cformula.CP.spec_var * Cformula.CP.spec_var list)) list)
  (need_preprocess: bool) (detect_dang: bool) -> let a = ([] : CF.hprel list) in
  let b = ([] : CF.hp_rel_def list) in
  (a, b)
)

let generate_lemma_helper iprog lemma_name coer_type ihps ihead ibody=
  (*generate ilemma*)
    let ilemma = I.mk_lemma (fresh_any_name lemma_name) coer_type ihps ihead ibody in
    (*transfrom ilemma to clemma*)
    let ldef = AS.case_normalize_coerc iprog ilemma in
    let l2r, r2l = AS.trans_one_coercion iprog ldef in
    l2r, r2l

let generate_lemma iprog cprog lemma_n coer_type lhs rhs ihead chead ibody cbody=
  (*check entailment*)
  let (res,_,_) =  if coer_type = I.Left then
    SC.sleek_entail_check [] cprog [(chead,cbody)] lhs (CF.struc_formula_of_formula rhs no_pos)
  else SC.sleek_entail_check [] cprog [(cbody,chead)] rhs (CF.struc_formula_of_formula lhs no_pos)
  in
  if res then
    let l2r, r2l = generate_lemma_helper iprog lemma_n coer_type [] ihead ibody in
    l2r, r2l
  else
    [],[]

let final_inst_analysis_view_x cprog vdef=
  let process_branch (r1,r2)vname args f=
    let hds, vns, hdrels = CF.get_hp_rel_formula f in
    if vns <> [] then (r1,r2) else
      let self_hds = List.filter (fun hd ->
          CP.is_self_spec_var hd.CF.h_formula_data_node
      ) hds in
      if self_hds = [] then
        let ( _,mix_f,_,_,_) = CF.split_components f in
        let eqNulls = CP.remove_dups_svl ((MCP.get_null_ptrs mix_f) ) in
        let self_eqNulls = List.filter (CP.is_self_spec_var) eqNulls in
        ([], self_eqNulls)
      else ( self_hds, [])
  in
  let vname = vdef.Cast.view_name in
  let args = vdef.Cast.view_vars in
  let s_hds, s_null = List.fold_left (fun (is_node, is_null) (f,_) ->
      process_branch (is_node, is_null) vname args f
  ) ([],[]) vdef.Cast.view_un_struc_formula
  in
  (s_hds, s_null)

let final_inst_analysis_view cprog vdef=
  let pr1 = Cprinter.string_of_view_decl in
  let pr2 hd= Cprinter.prtt_string_of_h_formula (CF.DataNode hd) in
  Debug.no_1 "final_inst_analysis_view" pr1 (pr_pair (pr_list pr2) !CP.print_svl)
      (fun _ -> final_inst_analysis_view_x cprog vdef) vdef

let subst_cont vn cont_args f ihf chf self_hns self_null pos=
  let rec subst_helper ss f0=
    match f0 with
      | CF.Base fb -> (* let _, vns, _ = CF.get_hp_rel_formula f0 in *)
        (* if (\* List.exists (fun hv -> String.compare hv.CF.h_formula_view_name vn = 0) vns *\) vns<> [] then *)
        (*   f0 *)
        (* else *)
            (* let nfb = CF.subst_b ss fb in *)
            let np = CP.subst_term ss (MCP.pure_of_mix fb.CF.formula_base_pure) in
            CF.Base {fb with CF.formula_base_pure = MCP.mix_of_pure np}
      | CF.Exists _ ->
            let qvars, base_f1 = CF.split_quantifiers f0 in
            let nf = subst_helper ss base_f1 in
            CF.add_quantifiers qvars nf
      | CF.Or orf ->
            CF.Or {orf with CF.formula_or_f1 = subst_helper ss orf.CF.formula_or_f1;
                CF.formula_or_f2 = subst_helper ss orf.CF.formula_or_f2;
            }
  in
  if self_null <> [] then
    let cont = match cont_args with
      | [a] -> a
      | _ -> report_error no_pos "Lemma.subst_cont: to handle"
    in
    let null_exp = CP.Null pos in
    let ss = [(cont, null_exp)] in
    (* let n = IP.Null no_pos in *)
    let ip = IP.mkEqExp (IP.Var (((CP.name_of_spec_var cont, CP.primed_of_spec_var cont)), no_pos)) (IP.Null no_pos) no_pos in
    let cp = CP.mkNull cont pos in
    (subst_helper ss f, IF.mkBase ihf ip IF.top_flow [] pos,
    CF.mkBase chf (MCP.mix_of_pure cp) CF.TypeTrue (CF.mkNormalFlow()) [] pos)
  else if self_hns <> [] then
    let _ = report_warning no_pos ("Lemma.subst_cont: to handle") in
    (f, IF.formula_of_heap_1 ihf pos, CF.formula_of_heap chf pos)
  else (f, IF.formula_of_heap_1 ihf pos, CF.formula_of_heap chf pos)

(*if two views are equiv (subsume), generate an equiv (left/right) lemma*)
let check_view_subsume iprog cprog view1 view2 need_cont_ana=
  let v_f1 = CF.formula_of_disjuncts (List.map fst view1.C.view_un_struc_formula) in
  let v_f2 = CF.formula_of_disjuncts (List.map fst view2.C.view_un_struc_formula) in
  let v_f11 = (* CF.formula_trans_heap_node (hn_c_trans (view1.C.view_name, view2.C.view_name)) *) v_f1 in
  let pos1 = (CF.pos_of_formula v_f1) in
  let pos2 = (CF.pos_of_formula v_f2) in
  let ihf1 = IF.mkHeapNode (self, Unprimed) (view1.C.view_name)
    0  false  (IP.ConstAnn Mutable) false false false None
    (List.map (fun (CP.SpecVar (_,id,p)) -> IP.Var ((id,p), pos1)) view1.C.view_vars) []  None pos1 in
  let chf1 = CF.mkViewNode (CP.SpecVar (Named view1.C.view_name,self, Unprimed)) view1.C.view_name
    view1.C.view_vars no_pos in
  let ihf2 = IF.mkHeapNode (self, Unprimed) (view2.C.view_name)
    0  false (IP.ConstAnn Mutable) false false false None
    (List.map (fun (CP.SpecVar (_,id,p)) -> IP.Var ((id,p), pos1)) view2.C.view_vars) [] None pos2 in
  let chf2 = CF.mkViewNode (CP.SpecVar (Named view2.C.view_name,self, Unprimed)) view2.C.view_name
    view2.C.view_vars no_pos in
  let v_f1, v_f2, iform_hf1, cform_hf1, iform_hf2, cform_hf2=
    if not need_cont_ana then
      (v_f11, v_f2, IF.formula_of_heap_1 ihf1 pos1, CF.formula_of_heap chf1 pos1,
      IF.formula_of_heap_1 ihf2 pos2, CF.formula_of_heap chf2 pos2)
    else
      if List.length view1.C.view_vars > List.length view2.C.view_vars && view1.C.view_cont_vars != [] then
        (* let _ = print_endline ("xxx1") in *)
        let self_hds, self_null = final_inst_analysis_view cprog view2 in
        let v_f12, ihf_12, cform_chf12 = subst_cont view1.C.view_name view1.C.view_cont_vars
          v_f11 ihf1 chf1 self_hds self_null pos1 in
        (v_f12, v_f2, ihf_12, cform_chf12, IF.formula_of_heap_1 ihf2 pos2, CF.formula_of_heap chf2 pos2)
      else if List.length view2.C.view_vars > List.length view1.C.view_vars && view2.C.view_cont_vars != [] then
        (* let _ = print_endline ("xxx2") in *)
        let self_hds, self_null = final_inst_analysis_view cprog view1 in
        let v_f22, ihf_22, cform_chf22 = subst_cont view2.C.view_name view2.C.view_cont_vars v_f2 ihf2 chf2 self_hds self_null pos2 in
        (v_f11, v_f22, IF.formula_of_heap_1 ihf1 pos1, CF.formula_of_heap chf1 pos1, ihf_22, cform_chf22)
      else (v_f11, v_f2, IF.formula_of_heap_1 ihf1 pos1, CF.formula_of_heap chf1 pos1,
      IF.formula_of_heap_1 ihf2 pos2, CF.formula_of_heap chf2 pos2)
  in
  let lemma_n = view1.C.view_name ^"_"^ view2.C.view_name in
  let l2r1, r2l1 = generate_lemma iprog cprog lemma_n I.Left v_f1 v_f2
    iform_hf1 cform_hf1 iform_hf2 cform_hf2 in
  let l2r2, r2l2 = generate_lemma iprog cprog lemma_n I.Right v_f1 v_f2
    iform_hf1 cform_hf1 iform_hf2 cform_hf2 in
  (l2r1@l2r2, r2l1@r2l2)

let generate_lemma_4_views_x iprog cprog=
  let rec helper views l_lem r_lem=
    match views with
      | [] -> (l_lem,r_lem)
      | [v] -> (l_lem,r_lem)
      | v::rest ->
            let l,r = List.fold_left (fun (r1,r2) v1 ->
                if List.length v.C.view_vars = List.length v1.C.view_vars then
                  let l, r = check_view_subsume iprog cprog v v1 false in
                  (r1@l,r2@r)
                else if (List.length v.C.view_vars > List.length v1.C.view_vars &&
                    List.length v.C.view_vars = List.length v1.C.view_vars + List.length v.C.view_cont_vars) ||
                  (List.length v.C.view_vars < List.length v1.C.view_vars &&
                      List.length v1.C.view_vars = List.length v.C.view_vars + List.length v1.C.view_cont_vars)
                then
                  (*cont paras + final inst analysis*)
                  (* let _ = report_warning no_pos ("cont paras + final inst analysis " ^ (v.C.view_name) ^ " ..." ^ *)
                  (*     v1.C.view_name) in *)
                  let l, r = check_view_subsume iprog cprog v v1 true in
                  (r1@l,r2@r)
                else
                  (r1,r2)
            ) ([],[]) rest
            in
            helper rest (l_lem@l) (r_lem@r)
  in
  let l2r, r2l = helper cprog.C.prog_view_decls [] [] in
  (* let _ = cprog.C.prog_left_coercions <- l2r @ cprog.C.prog_left_coercions in *)
  (* let _ = cprog.C.prog_right_coercions <- r2l @ cprog.C.prog_right_coercions in *)
  (l2r,r2l)

let generate_lemma_4_views iprog cprog=
  let pr1 cp = (pr_list_ln Cprinter.string_of_view_decl_short) cp.C.prog_view_decls in
  let pr2 = pr_list_ln Cprinter.string_of_coerc_short in
  Debug.no_1 "generate_lemma_4_views" pr1 (pr_pair pr2 pr2)
      (fun _ -> generate_lemma_4_views_x iprog cprog)
      cprog


(* Below are methods used for lemma transformation (ilemma->lemma), lemma proving and lemma store update *)


(* ilemma  ----> (left coerc list, right coerc list) *)
let process_one_lemma iprog cprog ldef = 
  let ldef = AS.case_normalize_coerc iprog ldef in
  let l2r, r2l = AS.trans_one_coercion iprog ldef in
  let l2r = List.concat (List.map (fun c-> AS.coerc_spec cprog c) l2r) in
  let r2l = List.concat (List.map (fun c-> AS.coerc_spec cprog c) r2l) in
  let _ = if (!Globals.print_input || !Globals.print_input_all) then 
    let _ = print_string (Iprinter.string_of_coerc_decl ldef) in 
    let _ = print_string ("\nleft:\n " ^ (Cprinter.string_of_coerc_decl_list l2r) ^"\n right:\n"^ (Cprinter.string_of_coerc_decl_list r2l) ^"\n") in
    () else () in
  (l2r,r2l,ldef.I.coercion_type)


(* ilemma repo ----> (left coerc list, right coerc list) *)
let process_one_repo repo iprog cprog = 
  List.map (fun ldef -> 
      let l2r,r2l,typ = process_one_lemma iprog cprog ldef in
      (l2r,r2l,typ,(ldef.I.coercion_name))
  ) repo

let verify_one_repo lems cprog = 
  let res = List.fold_left (fun ((fail_ans,res_so_far) as res) (l2r,r2l,typ,name) ->
      match fail_ans with
        | None ->
            let res = LP.verify_lemma 3 l2r r2l cprog name typ in 
            let chk_for_fail =  if !Globals.disable_failure_explaining then CF.isFailCtx else CF.isFailCtx_gen in
            let res_so_far = res::res_so_far in
            let fail = if chk_for_fail res then Some (name^":"^(Cprinter.string_of_coercion_type typ)) else None in
            (fail, res_so_far)
            (* ((if CF.isFailCtx res then Some (name^":"^(Cprinter.string_of_coercion_type typ)) else None), res_so_far) *)
        | Some n ->
              res
  ) (None,[]) lems in
  res


(* update the lemma store with the lemmas in repo and check for their validity *)
let update_store_with_repo_x repo iprog cprog =
  let lems = process_one_repo repo iprog cprog in
  let left  = List.concat (List.map (fun (a,_,_,_)-> a) lems) in
  let right = List.concat (List.map (fun (_,a,_,_)-> a) lems) in
  let _ = Lem_store.all_lemma # add_coercion left right in
  let (invalid_lem, lctx) =  verify_one_repo lems cprog in
  (invalid_lem, lctx)

let update_store_with_repo repo iprog cprog =
  let pr1 = pr_list Iprinter.string_of_coerc_decl in
  let pr_out = pr_pair (pr_opt pr_id) (pr_list Cprinter.string_of_list_context) in 
  Debug.no_1 "update_store_with_repo"  pr1 pr_out (fun _ -> update_store_with_repo_x repo iprog cprog) repo

(* pop only if repo is invalid *)
(* return None if all succeed, and result of first failure otherwise *)
let manage_safe_lemmas repo iprog cprog = 
  let (invalid_lem, nctx) = update_store_with_repo repo iprog cprog in
  match invalid_lem with
    | Some name -> 
          let _ = Log.last_cmd # dumping (name) in
          let _ = print_endline ("\nFailed to prove "^ (name) ^ " in current context.") in
          Lem_store.all_lemma # pop_coercion;
          let _ = print_endline ("Removing invalid lemma ---> lemma store restored.") in
          Some([List.hd(nctx)])
    | None ->
          let lem_str = pr_list pr_id (List.map (fun i -> 
              i.I.coercion_name^":"^(Cprinter.string_of_coercion_type i.I.coercion_type)) repo) in
          let _ = print_endline ("\nValid Lemmas : "^lem_str^" added to lemma store.") in
          None

(* update store with given repo without verifying the lemmas *)
let manage_unsafe_lemmas repo iprog cprog: (CF.list_context list option) = 
  let (left,right) = List.fold_left (fun (left,right) ldef -> 
      let l2r,r2l,typ = process_one_lemma iprog cprog ldef in
      (l2r@left,r2l@right)
  ) ([],[]) repo in
  let _ = Lem_store.all_lemma # add_coercion left right in
  let _ = Debug.info_ihprint (add_str "\nUpdated store with unsafe repo." pr_id) "" no_pos in
  None

let manage_lemmas repo iprog cprog =
  if !Globals.check_coercions then manage_safe_lemmas repo iprog cprog 
  else manage_unsafe_lemmas repo iprog cprog 

(* update store with given repo, but pop it out in the end regardless of the result of lemma verification *)
(* let manage_test_lemmas repo iprog cprog orig_ctx =  *)
(*   let new_ctx = CF.SuccCtx [CF.empty_ctx (CF.mkTrueFlow ()) Lab2_List.unlabelled no_pos] in  *)
(*   (\* what is the purpose of new_ctx? *\) *)
(*   let (invalid_lem, nctx) = update_store_with_repo repo iprog cprog new_ctx in *)
(*   Lem_store.all_lemma # pop_coercion; *)
(*   let _  = match nctx with *)
(*     | CF.FailCtx _ ->  *)
(*           let _ = Log.last_cmd # dumping (invalid_lem) in *)
(*           print_endline ("\nFailed to prove "^(invalid_lem) ^ " ==> invalid repo in current context.") *)
(*     | CF.SuccCtx _ -> *)
(*           print_endline ("\nTemp repo proved valid in current context.") in *)
(*   let _ = print_endline ("Removing temp repo ---> lemma store restored.") in *)
(*   Some nctx *)


(* update store with given repo, but pop it out in the end regardless of the result of lemma verification *)
(* return None if all succeed, return first failed ctx otherwise *)
let manage_infer_lemmas str repo iprog cprog = 
  let (invalid_lem, nctx) = update_store_with_repo repo iprog cprog in
  Lem_store.all_lemma # pop_coercion;
  match invalid_lem with
    | Some name -> 
          let _ = Log.last_cmd # dumping (name) in
          let _ = print_endline ("\nFailed to "^str^" for "^ (name) ^ " ==> invalid lemma encountered.") in
          false,Some([List.hd(nctx)])
    | None ->
          let _ = print_endline ("\n Temp Lemma(s) "^str^" as valid in current context.") in
          true,Some nctx


(* verify  a list of lemmas *)
(* if one of them fails, return failure *)
(* otherwise, return a list of their successful contexts 
   which may contain inferred result *)
let sa_verify_one_repo cprog l2r r2l = 
  let res = List.fold_left (fun ((valid_ans,res_so_far) as res) coer ->
      match valid_ans with
        | true ->
              let (flag,lc) = LP.sa_verify_lemma cprog coer in 
              (flag, lc::res_so_far)
        | false -> res
  ) (true,[]) (l2r@r2l) in
  res

(* update the lemma store with the lemmas in repo and check for their validity *)
let sa_update_store_with_repo cprog l2r r2l =
   let _ = Lem_store.all_lemma # add_coercion l2r r2l in
   let (invalid_lem, lctx) =  sa_verify_one_repo cprog l2r r2l in
   (invalid_lem, lctx)

(* l2r are left to right_lemmas *)
(* r2l are right to right_lemmas *)
(* return None if some failure; return list of contexts if all succeeded *)
let sa_infer_lemmas iprog cprog lemmas  = 
  (* let (l2r,others) = List.partition (fun c -> c.C.coercion_type==I.Left) lemmas in  *)
  (* let (r2l,equiv) = List.partition (fun c -> c.C.coercion_type==I.Right) others in  *)
  (* let l2r = l2r@(List.map (fun c -> {c with C.coercion_type = I.Left} ) equiv) in *)
  (* let r2l = r2l@(List.map (fun c -> {c with C.coercion_type = I.Right} ) equiv) in *)
  (* let (valid_lem, nctx) = sa_update_store_with_repo cprog l2r r2l in *)
  (* Lem_store.all_lemma # pop_coercion; *)
  (* match valid_lem with *)
  (*   | false ->  *)
  (*         (\* let _ = Log.last_cmd # dumping (name) in *\) *)
  (*         let _ = Debug.tinfo_pprint ("\nFailed to prove a lemma ==> during sa_infer_lemmas.") no_pos in *)
  (*         None *)
  (*   | true -> Some nctx *)
  let (invalid_lem, nctx) = update_store_with_repo lemmas iprog cprog in
  Lem_store.all_lemma # pop_coercion;
   match invalid_lem with
    | Some name -> 
          let _ = Debug.tinfo_pprint ("\nFailed to prove a lemma ==> during sa_infer_lemmas.") no_pos in
          None
    | None ->
          Some nctx

let sa_infer_lemmas iprog cprog lemmas  =
  let pr1 = pr_list pr_none in
  Debug.no_1 "sa_infer_lemmas" pr1 pr_none (fun _ -> sa_infer_lemmas iprog cprog lemmas) lemmas

(*pure*)
let partition_pure_oblgs constrs post_rel_ids=
  let pre_invs, pre_constrs, post_constrs = List.fold_left (fun (r0,r1,r2) (cat,lhs_p,rhs_p) ->
      match cat with
        | CP.RelAssume _ | CP.RelDefn _ -> begin
            try
              let rel = CP.name_of_rel_form rhs_p in
              if CP.mem_svl rel post_rel_ids then
                r0,r1,r2@[(lhs_p, rhs_p)]
              else
                if CP.isConstTrue rhs_p then
                  (r0@[lhs_p], r1, r2)
                else
                  (r0, r1@[(lhs_p, rhs_p)], r2)
            with _ ->
                if CP.isConstTrue rhs_p then
                  (r0@[(lhs_p)], r1, r2)
                else (r0, r1@[(lhs_p, rhs_p)], r2)
          end
        | _ -> (r0,r1,r2)
  ) ([],[],[]) constrs in
  (pre_invs, pre_constrs, post_constrs)

(*todo: use the following precedure for manage_infer_pred_lemmas*)
let preprocess_fixpoint_computation cprog xpure_fnc lhs oblgs rel_ids post_rel_ids =
  let pre_invs, pre_rel_oblgs, post_rel_oblgs = partition_pure_oblgs oblgs post_rel_ids in
  let pre_rel_ids = CP.diff_svl rel_ids post_rel_ids in
  let proc_spec = CF.mkETrue_nf no_pos in
  let _,bare = CF.split_quantifiers lhs in
  let pres,posts_wo_rel,all_posts,inf_vars,pre_fmls,grp_post_rel_flag = 
    CF.get_pre_post_vars [] xpure_fnc (CF.struc_formula_of_formula bare no_pos) cprog in
  let _ = Debug.ninfo_hprint (add_str "pre_fmls" (pr_list !CP.print_formula)) pre_fmls no_pos in
  let pre_rel_fmls = List.concat (List.map CF.get_pre_rels pre_fmls) in
  let pre_rel_fmls = List.filter (fun x -> CP.intersect (CP.get_rel_id_list x) inf_vars != []) pre_rel_fmls in
  let pre_vnodes = CF.get_views bare in
  let ls_rel_args = CP.get_list_rel_args (CF.get_pure bare) in
  let _ = Debug.ninfo_hprint (add_str "coercion_body" !CF.print_formula) bare no_pos in
  (* let _ = Debug.info_hprint (add_str "pre_rel_ids" !CP.print_svl) pre_rel_ids no_pos in *)
  let pre_rel_args = List.fold_left (fun r (rel_id,args)-> if CP.mem_svl rel_id pre_rel_ids then r@args
  else r
  ) [] ls_rel_args in
  let invs = List.map (FP.get_inv cprog pre_rel_args) pre_vnodes in
  let rel_fm = CP.filter_var (CF.get_pure bare) pre_rel_args in
  (* let invs = CF.get_pre_invs pre_rel_ids (FP.get_inv cprog) *)
  (*   (CF.struc_formula_of_formula coer.C.coercion_body no_pos) in *)
  let inv = List.fold_left (fun p1 p2 -> CP.mkAnd p1 p2 no_pos) rel_fm (pre_invs@invs) in
  let pre_inv_ext = [inv] in
  FP.rel_fixpoint_wrapper pre_inv_ext pre_fmls pre_rel_oblgs post_rel_oblgs pre_rel_ids post_rel_ids proc_spec
      (*grp_post_rel_flag*)1

let manage_infer_pred_lemmas repo iprog cprog xpure_fnc=
  let rec helper coercs rel_fixs res_so_far=
    match coercs with
      | [] -> (rel_fixs, Some res_so_far)
      | coer::rest -> begin
          let lems = process_one_repo [coer] iprog cprog in
          let left  = List.concat (List.map (fun (a,_,_,_)-> a) lems) in
          let right = List.concat (List.map (fun (_,a,_,_)-> a) lems) in
          let _ = Lem_store.all_lemma # add_coercion left right in
          let (invalid_lem, lcs) =  verify_one_repo lems cprog in
          Lem_store.all_lemma # pop_coercion;
          match invalid_lem with
            | None ->
                  let hprels = List.fold_left (fun r_ass lc -> r_ass@(Infer.collect_hp_rel_list_context lc)) [] lcs in
                  let (_,hp_rest) = List.partition (fun hp ->
                      match hp.CF.hprel_kind with
                        | CP.RelDefn _ -> true
                        | _ -> false
                  ) hprels
                  in
                  let (hp_lst_assume,(* hp_rest *)_) = List.partition (fun hp ->
                      match hp.CF.hprel_kind with
                        | CP.RelAssume _ -> true
                        | _ -> false
                  ) hp_rest
                  in
                  let oblgs = List.fold_left (fun r_ass lc -> r_ass@(Infer.collect_rel_list_context lc)) [] lcs in
                  (*left*)
                  let rl =
                    if left = [] then [] else
                      (*shape*)
                      let post_hps, post_rel_ids, sel_hps, rel_ids = match left  with
                        | [] -> [],[],[],[]
                        | [coer] -> (CP.remove_dups_svl (CF.get_hp_rel_name_formula coer.C.coercion_body),
                          CP.remove_dups_svl (List.map fst (CP.get_list_rel_args (CF.get_pure coer.C.coercion_body))),
                          List.filter (fun sv -> CP.is_hprel_typ sv) coer.C.coercion_infer_vars,
                          List.filter (fun sv -> CP.is_rel_typ sv) coer.C.coercion_infer_vars
                          )
                        | _ -> report_error no_pos "LEMMA: manage_infer_pred_lemmas"
                      in
                      let _ = if sel_hps = [] || hp_lst_assume = [] then () else
                        let _, hp_defs = !infer_shapes iprog cprog "temp" hp_lst_assume sel_hps post_hps
                          [] [] [] true true in
                        ()
                      in
                      (*pure fixpoint*)
                      let rl = if rel_ids = [] || oblgs = [] then [] else
                        let pre_invs, pre_rel_oblgs, post_rel_oblgs = partition_pure_oblgs oblgs post_rel_ids in
                        let proc_spec = CF.mkETrue_nf no_pos in
                        let pre_rel_ids = CP.diff_svl rel_ids post_rel_ids in
                        let r = FP.rel_fixpoint_wrapper pre_invs [] pre_rel_oblgs post_rel_oblgs pre_rel_ids post_rel_ids proc_spec 1 in
                        let _ = Debug.info_hprint (add_str "fixpoint"
                            (let pr1 = Cprinter.string_of_pure_formula in pr_list_ln (pr_quad pr1 pr1 pr1 pr1))) r no_pos in
                        let _ = print_endline "" in
                        r
                      in
                      rl
                  in
                  (*right*)
                  (*shape*)
                  let rr = if right = [] then [] else
                    let post_hps, post_rel_ids, sel_hps, rel_ids = match right  with
                      | [] -> [],[],[],[]
                      | [coer] -> (CP.remove_dups_svl (CF.get_hp_rel_name_formula coer.C.coercion_head),
                        CP.remove_dups_svl (List.map fst (CP.get_list_rel_args (CF.get_pure coer.C.coercion_head))),
                        List.filter (fun sv -> CP.is_hprel_typ sv) coer.C.coercion_infer_vars,
                        List.filter (fun sv -> CP.is_rel_typ sv) coer.C.coercion_infer_vars
                        )
                      | _ -> report_error no_pos "LEMMA: manage_infer_pred_lemmas 2"
                    in
                    let _ = if sel_hps = [] || hp_lst_assume = [] then () else
                      let _, hp_defs = !infer_shapes iprog cprog "temp" hp_lst_assume sel_hps post_hps
                        [] [] [] true true in
                      ()
                    in
                    (*pure fixpoint*)
                    let rr = if rel_ids = [] || oblgs = [] then [] else
                      let pre_invs, pre_rel_oblgs, post_rel_oblgs = partition_pure_oblgs oblgs post_rel_ids in
                      let pre_rel_ids = CP.diff_svl rel_ids post_rel_ids in
                      let proc_spec = CF.mkETrue_nf no_pos in
                      (*more invs*)
                      let pre_inv_ext,pre_fmls,grp_post_rel_flag = match right with
                        | [] -> [],[],0
                        | [coer] ->
                              let _,bare = CF.split_quantifiers coer.C.coercion_body in
                              let pres,posts_wo_rel,all_posts,inf_vars,pre_fmls,grp_post_rel_flag = 
                                CF.get_pre_post_vars [] xpure_fnc (CF.struc_formula_of_formula bare no_pos) cprog in
                              let _ = Debug.ninfo_hprint (add_str "pre_fmls" (pr_list !CP.print_formula)) pre_fmls no_pos in
                              let pre_rel_fmls = List.concat (List.map CF.get_pre_rels pre_fmls) in
                              let pre_rel_fmls = List.filter (fun x -> CP.intersect (CP.get_rel_id_list x) inf_vars != []) pre_rel_fmls in
                              let pre_vnodes = CF.get_views coer.C.coercion_body in
                              let ls_rel_args = CP.get_list_rel_args (CF.get_pure bare) in
                              let _ = Debug.ninfo_hprint (add_str "coercion_body" !CF.print_formula) bare no_pos in
                              (* let _ = Debug.info_hprint (add_str "pre_rel_ids" !CP.print_svl) pre_rel_ids no_pos in *)
                              let pre_rel_args = List.fold_left (fun r (rel_id,args)-> if CP.mem_svl rel_id pre_rel_ids then r@args
                              else r
                              ) [] ls_rel_args in
                              let invs = List.map (FP.get_inv cprog pre_rel_args) pre_vnodes in
                              let rel_fm = CP.filter_var (CF.get_pure bare) pre_rel_args in
                              let inv = List.fold_left (fun p1 p2 -> CP.mkAnd p1 p2 no_pos) rel_fm (pre_invs@invs) in
                              [inv],pre_fmls,grp_post_rel_flag
                        | _ -> report_error no_pos "LEMMA: manage_infer_pred_lemmas 3"
                      in
                      let r = FP.rel_fixpoint_wrapper pre_inv_ext pre_fmls pre_rel_oblgs post_rel_oblgs pre_rel_ids post_rel_ids proc_spec grp_post_rel_flag in
                      (* let _ = Debug.info_hprint (add_str "fixpoint" *)
                      (*     (let pr1 = Cprinter.string_of_pure_formula in pr_list_ln (pr_quad pr1 pr1 pr1 pr1))) r no_pos in *)
                      (* let _ = print_endline "" in *)
                      r
                    in
                    (rr)
                  in
                  (* let _=  print_endline "*************************************" in *)
                  helper rest (rel_fixs@rl@rr) (res_so_far@lcs)
            | Some _ -> (rel_fixs, None)
        end
  in
  helper repo [] []

(* for lemma_test, we do not return outcome of lemma proving *)
let manage_test_lemmas repo iprog cprog = 
  manage_infer_lemmas "proved" repo iprog cprog; None (*Loc: while return None? instead full result*)

let manage_test_lemmas1 repo iprog cprog = 
  manage_infer_lemmas "proved" repo iprog cprog

let manage_infer_lemmas repo iprog cprog = 
   (manage_infer_lemmas "inferred" repo iprog cprog)

(* verify given repo in a fresh store. Revert the store back to it's state prior to this method call *)
(* let manage_test_new_lemmas repo iprog cprog ctx =  *)
(*   let left_lems = Lem_store.all_lemma # get_left_coercion in *)
(*   let right_lems = Lem_store.all_lemma # get_right_coercion in *)
(*   let _ = Lem_store.all_lemma # set_coercion [] [] in *)
(*   let (invalid_lem, nctx) = update_store_with_repo repo iprog cprog ctx in *)
(*   let _ = Lem_store.all_lemma # set_left_coercion left_lems in *)
(*   let _ = Lem_store.all_lemma # set_right_coercion right_lems in *)
(*   let _ = match nctx with  *)
(*     | CF.FailCtx _ ->  *)
(*           let _ = Log.last_cmd # dumping (invalid_lem) in *)
(*           print_endline ("\nFailed to prove "^ (invalid_lem) ^ " ==> invalid repo in fresh context.") *)
(*     | CF.SuccCtx _ -> *)
(*           print_endline ("\nTemp repo proved valid in fresh context.") in *)
(*   print_endline ("Removing temp repo ---> lemma store restored."); *)
(*   Some ctx *)

(* verify given repo in a fresh store. Revert the store back to it's state prior to this method call *)
let manage_test_new_lemmas repo iprog cprog = 
   let left_lems = Lem_store.all_lemma # get_left_coercion in
   let right_lems = Lem_store.all_lemma # get_right_coercion in
   let _ = Lem_store.all_lemma # set_coercion [] [] in
   let res = manage_test_lemmas repo iprog cprog in
   let _ = Lem_store.all_lemma # set_left_coercion left_lems in
   let _ = Lem_store.all_lemma # set_right_coercion right_lems in
   res

let manage_test_new_lemmas1 repo iprog cprog = 
   let left_lems = Lem_store.all_lemma # get_left_coercion in
   let right_lems = Lem_store.all_lemma # get_right_coercion in
   let _ = Lem_store.all_lemma # clear_left_coercion in
   let _ = Lem_store.all_lemma # clear_right_coercion in
   let res = manage_test_lemmas1 repo iprog cprog in
   let _ = Lem_store.all_lemma # set_left_coercion left_lems in
   let _ = Lem_store.all_lemma # set_right_coercion right_lems in
   res


let do_unfold_view_hf cprog hf0 =
  let fold_fnc ls1 ls2 aux_fnc = List.fold_left (fun r (hf2, p2) ->
      let in_r = List.map (fun (hf1, p1) ->
          let nh = aux_fnc hf1 hf2 in
          let _ = Debug.info_hprint (add_str "        p1:" !CP.print_formula) (MCP.pure_of_mix p1) no_pos in
          let _ = Debug.info_hprint (add_str "        p2:" !CP.print_formula) (MCP.pure_of_mix p2) no_pos in
          let qvars1, bare1 = CP.split_ex_quantifiers (MCP.pure_of_mix p1) in
          let qvars2, bare2 = CP.split_ex_quantifiers (MCP.pure_of_mix p2) in
          let _ = Debug.info_hprint (add_str "        bare1:" !CP.print_formula) bare1 no_pos in
          let _ = Debug.info_hprint (add_str "        bare2:" !CP.print_formula) bare2 no_pos in
          let np = CP.mkAnd bare1 bare2 (CP.pos_of_formula bare1) in
          (nh, MCP.mix_of_pure (CP.add_quantifiers (CP.remove_dups_svl (qvars1@qvars2)) np))
      ) ls1 in
      r@in_r
  ) [] ls2 in
  let rec helper hf=
    match hf with
      | CF.Star { CF.h_formula_star_h1 = hf1;
        CF.h_formula_star_h2 = hf2;
        CF.h_formula_star_pos = pos} ->
            let ls_hf_p1 = helper hf1 in
            let ls_hf_p2 = helper hf2 in
            let star_fnc h1 h2 =
              CF.Star {CF.h_formula_star_h1 = h1;
              CF.h_formula_star_h2 = h2;
              CF.h_formula_star_pos = pos}
            in
            fold_fnc ls_hf_p1 ls_hf_p2 star_fnc
      | CF.StarMinus { h_formula_starminus_h1 = hf1;
        CF.h_formula_starminus_h2 = hf2;
        CF.h_formula_starminus_aliasing = al;
        CF.h_formula_starminus_pos = pos} ->
            let ls_hf_p1 = helper hf1 in
            let ls_hf_p2 = helper hf2 in
            let starminus_fnc h1 h2 =
              CF.StarMinus {CF.h_formula_starminus_h1 = h1;
              CF.h_formula_starminus_h2 = h2;
               CF.h_formula_starminus_aliasing = al;
               CF.h_formula_starminus_pos = pos}
            in
            fold_fnc ls_hf_p1 ls_hf_p2 starminus_fnc
      | CF.ConjStar  { CF.h_formula_conjstar_h1 = hf1;
        CF.h_formula_conjstar_h2 = hf2;
        CF.h_formula_conjstar_pos = pos} ->
          let ls_hf_p1 = helper hf1 in
          let ls_hf_p2 = helper hf2 in
          let conjstar_fnc h1 h2 = CF.ConjStar { CF.h_formula_conjstar_h1 = h1;
          CF.h_formula_conjstar_h2 = h2;
          CF.h_formula_conjstar_pos = pos}
          in
          fold_fnc ls_hf_p1 ls_hf_p2 conjstar_fnc
      | CF.ConjConj { CF.h_formula_conjconj_h1 = hf1;
        CF.h_formula_conjconj_h2 = hf2;
        CF.h_formula_conjconj_pos = pos} ->
            let ls_hf_p1 = helper hf1 in
            let ls_hf_p2 = helper hf2 in
            let conjconj_fnc h1 h2 = CF.ConjConj { CF.h_formula_conjconj_h1 = h1;
            CF.h_formula_conjconj_h2 = h2;
            CF.h_formula_conjconj_pos = pos}
            in
            fold_fnc ls_hf_p1 ls_hf_p2 conjconj_fnc
      | CF.Phase { h_formula_phase_rd = hf1;
        CF.h_formula_phase_rw = hf2;
        CF.h_formula_phase_pos = pos} ->
            let ls_hf_p1 = helper hf1 in
            let ls_hf_p2 = helper hf2 in
            let phase_fnc h1 h2 = CF.Phase { CF.h_formula_phase_rd = h1;
              CF.h_formula_phase_rw = h2;
              CF.h_formula_phase_pos = pos}
            in
            fold_fnc ls_hf_p1 ls_hf_p2 phase_fnc
      | CF.Conj { CF.h_formula_conj_h1 = hf1;
        CF.h_formula_conj_h2 = hf2;
        CF.h_formula_conj_pos = pos} ->
          let ls_hf_p1 = helper hf1 in
          let ls_hf_p2 = helper hf2 in
          let conj_fnc h1 h2 = CF.Conj { CF.h_formula_conj_h1 = h1;
          CF.h_formula_conj_h2 = h2;
          CF.h_formula_conj_pos = pos}
          in
          fold_fnc ls_hf_p1 ls_hf_p2 conj_fnc
      | CF.ViewNode hv -> begin
            try
              let vdcl = C.look_up_view_def_raw 40 cprog.C.prog_view_decls hv.CF.h_formula_view_name in
              let fs = List.map fst vdcl.C.view_un_struc_formula in
              let f_args = (CP.SpecVar (Named vdcl.C.view_name,self, Unprimed))::vdcl.C.view_vars in
              let a_args = hv.CF.h_formula_view_node::hv.CF.h_formula_view_arguments in
              let ss = List.combine f_args  a_args in
              let fs1 = List.map (CF.subst ss) fs in
              List.map (fun f -> (List.hd (CF.heap_of f), MCP.mix_of_pure (CF.get_pure f))) fs1
            with _ -> let _ = report_warning no_pos ("LEM.do_unfold_view_hf: can not find view " ^ hv.CF.h_formula_view_name) in
            [(CF.HTrue, MCP.mix_of_pure (CP.mkTrue no_pos))]
        end
      | CF.DataNode _  | CF.HRel _ | CF.Hole _
      | CF.HTrue  | CF.HFalse | CF.HEmp -> [(hf, MCP.mix_of_pure (CP.mkTrue no_pos))]
  in
  helper hf0

let do_unfold_view_x cprog (f0: CF.formula) =
  let rec helper f=
  match f with
    | CF.Base fb ->
          let ls_hf_pure = do_unfold_view_hf cprog fb.CF.formula_base_heap in
          let fs = List.map (fun (hf, p) ->
              let _ = Debug.ninfo_hprint (add_str "        p:" !CP.print_formula) (MCP.pure_of_mix p) no_pos in
              let qvars0, bare_f = CP.split_ex_quantifiers_ext (CP.elim_exists (MCP.pure_of_mix  p)) in
               let _ = Debug.ninfo_hprint (add_str "        bare_f:" !CP.print_formula) bare_f no_pos in
              let f = CF.Base {fb with CF.formula_base_heap = hf;
                  CF.formula_base_pure = MCP.merge_mems (MCP.mix_of_pure bare_f) fb.CF.formula_base_pure true;
              }
              in CF.add_quantifiers qvars0 f
          ) ls_hf_pure in
          CF.disj_of_list fs fb.CF.formula_base_pos
    | CF.Exists _ ->
          let qvars, base1 = CF.split_quantifiers f in
          let nf = helper base1 in
          CF.add_quantifiers qvars nf
    | CF.Or orf  ->
          CF.Or { orf with CF.formula_or_f1 = helper orf.CF.formula_or_f1;
              CF.formula_or_f2 = helper orf.CF.formula_or_f2 }
  in
  helper f0

let do_unfold_view cprog (f0: CF.formula) =
  let pr1 = Cprinter.prtt_string_of_formula in
  Debug.no_1 "LEM.do_unfold_view" pr1 pr1
      (fun _ -> do_unfold_view_x cprog f0) f0

let checkeq_sem_x iprog0 cprog0 f1 f2 hpdefs=
  (*************INTERNAL******************)
  let back_up_progs iprog cprog=
    (iprog.I.prog_view_decls, iprog.I.prog_hp_decls, cprog.C.prog_view_decls, cprog.C.prog_hp_decls,
    Lem_store.all_lemma # get_left_coercion, Lem_store.all_lemma # get_right_coercion)
  in
  let reset_progs (ivdecls, ihpdecls, cvdecls, chpdecls, left_coers, righ_coers)=
    let _ = iprog0.I.prog_view_decls <- ivdecls in
    let _ = iprog0.I.prog_hp_decls <- ihpdecls in
    let _ = cprog0.C.prog_view_decls <- cvdecls in
    let _ = cprog0.C.prog_hp_decls <- chpdecls in
    let _ = Lem_store.all_lemma # set_coercion left_coers righ_coers in
    ()
  in
  let rec look_up_hpdef rem_hpdefs (r_unk_hps, r_hpdefs) hp=
    match rem_hpdefs with
      | [] -> (r_unk_hps@[hp], r_hpdefs)
      | ((* (k, _,_,_) as *) hpdef)::rest -> begin
          match hpdef.CF.def_cat with
            | CP.HPRelDefn (hp1,_,_) -> if CP.eq_spec_var hp hp1 then
                (*to remove after improve the algo with nested*)
                let _ = List.map (fun (f,_) ->
                    let hps = CF.get_hp_rel_name_formula f in
                    if CP.diff_svl hps [hp] != [] then
                      raise Not_found
                    else []
                )  hpdef.CF.def_rhs in
                (r_unk_hps, r_hpdefs@[hpdef])
              else look_up_hpdef rest (r_unk_hps, r_hpdefs) hp
            | _ -> look_up_hpdef rest (r_unk_hps, r_hpdefs) hp
        end
  in
  let heap_remove_unk_hps unk_hps hn = match hn with
    | CF.HRel (hp,eargs, pos)-> begin
        if CP.mem_svl hp unk_hps then CF.HTrue else hn
      end
    | _ -> hn
  in
  (*************END INTERNAL******************)
  (*for each proving: generate lemma; cyclic proof*)
  try begin
  let bc = back_up_progs iprog0 cprog0 in
  let hps = CP.remove_dups_svl ((CF.get_hp_rel_name_formula f1)@(CF.get_hp_rel_name_formula f2)) in
  let unk_hps, known_hpdefs = List.fold_left (look_up_hpdef hpdefs) ([],[]) hps in
  (*remove unk_hps*)
  let f11,f21 = if unk_hps = [] then (f1, f2) else
    (CF.formula_trans_heap_node (heap_remove_unk_hps unk_hps) f1,
    CF.formula_trans_heap_node (heap_remove_unk_hps unk_hps) f2)
  in
  (*transform hpdef to view;
    if preds are unknown -> HTRUE
  *)
  let proc_name = "eqproving" in
  let n_cview,chprels_decl = SAO.trans_hprel_2_cview iprog0 cprog0 proc_name known_hpdefs in
  (*trans_hp_view_formula*)
  let f12 = SAO.trans_formula_hp_2_view iprog0 cprog0 proc_name chprels_decl known_hpdefs [] f11 in
  let f22 = SAO.trans_formula_hp_2_view iprog0 cprog0 proc_name chprels_decl known_hpdefs [] f21 in
  (*iform*)
  let if12 = AS.rev_trans_formula f12 in
  let if22 = AS.rev_trans_formula f22 in
  (*unfold lhs - rhs*)
  let f13 = do_unfold_view cprog0 f12 in
  let f23 = do_unfold_view cprog0 f22 in
  let r=
    let lemma_name = "tmp" in
    let l_coer = I.mk_lemma (fresh_any_name lemma_name) I.Left [] if12 if22 in
    let r1,_ = manage_test_new_lemmas1 [l_coer] iprog0 cprog0 in
    (* let fnc = wrap_proving_kind PK_SA_EQUIV (fun f1 f2 -> SC.sleek_entail_check [] cprog0 [(\* (f12,f22) *\)] f1 (CF.struc_formula_of_formula f2 no_pos)) in *)
    (* let r1,_,_ = SC.sleek_entail_check [] cprog0 [(\* (f12,f22) *\)] f13 (CF.struc_formula_of_formula f23 no_pos) in *)
    (* let r1,_,_ = fnc f13 f23 in *)
    if not r1 then false else
      let r_coer = I.mk_lemma (fresh_any_name lemma_name) I.Left [] if22 if12 in
      let r2,_ = manage_test_new_lemmas1 [r_coer] iprog0 cprog0 in
      (* let r2,_,_ = SC.sleek_entail_check [] cprog0 [(\* (f22,f12) *\)] f23 (CF.struc_formula_of_formula f13 no_pos) in *)
      (* let r2,_,_ = fnc f23 f13 in *)
      r2
  in
  let _ = reset_progs bc in
  r
  end
  with _ -> let _ = Debug.info_hprint (add_str "view_equivs: " pr_id) "1" no_pos in
  false

let checkeq_sem iprog cprog f1 f2 hpdefs=
  let pr1 = Cprinter.prtt_string_of_formula in
  let pr2 = pr_list_ln Cprinter.string_of_hp_rel_def in
  Debug.no_3 "LEM.checkeq_sem" pr1 pr1 pr2 string_of_bool
      (fun _ _ _ ->  checkeq_sem_x iprog cprog f1 f2 hpdefs)
      f1 f2 hpdefs



let _ = Sleekcore.generate_lemma := generate_lemma_helper;;
let _ = Solver.manage_unsafe_lemmas := manage_unsafe_lemmas;;
