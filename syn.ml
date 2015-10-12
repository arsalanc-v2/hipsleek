#include "xdebug.cppo"
open VarGen
open Globals
open Gen
open Others
open Label_only
open SynUtils
open Exc.GTable
module C = Cast
module I = Iast
module CP = Cpure
module IF = Iformula
module CF = Cformula
module CVU = Cvutil
module MCP = Mcpure
(* module CEQ = Checkeq *)

(**************************)
(***** SIMPLIFICATION *****)
(**************************)

let pr_hprel_list = Cprinter.string_of_hprel_list_short

let simplify_hprel_list hprels = 
  List.map (x_add_1 simplify_hprel) hprels

(***************************)
(***** ADDING DANGLING *****)
(***************************)

let dangling_view_name = "Dangling"

let mk_dangling_view_prim = 
  Cast.mk_view_prim dangling_view_name [] (MCP.mkMTrue no_pos) no_pos

let mk_dangling_view_node dangling_var = 
  CF.mkViewNode dangling_var dangling_view_name [] no_pos

let add_dangling_hprel prog (hpr: CF.hprel) =
  if is_post_hprel hpr then
    let () = y_tinfo_pp ("Do not add dangling into the post-hprel " ^ (Cprinter.string_of_hprel_short hpr)) in
    hpr, false
  else
    let _, lhs_p, _, _, _, _ = x_add_1 CF.split_components hpr.hprel_lhs in
    let lhs_aliases = MCP.ptr_equations_with_null lhs_p in
    let guard_aliases =
      match hpr.hprel_guard with
      | None -> []
      | Some g -> 
        let _, guard_p, _, _, _, _ = x_add_1 CF.split_components g in
        MCP.ptr_equations_with_null guard_p
    in
    let aliases = CP.find_all_closures (lhs_aliases @ guard_aliases) in
    let () = y_tinfo_hp (add_str "aliases" (pr_list !CP.print_svl)) aliases in
    let null_aliases =
      try List.find (fun svl -> List.exists CP.is_null_const svl) aliases
      with _ -> []
    in
    let lhs_args = collect_feasible_heap_args_formula prog null_aliases hpr.hprel_lhs in
    let lhs_nodes = CF.collect_node_var_formula hpr.hprel_lhs in
    let rhs_args = collect_feasible_heap_args_formula prog null_aliases hpr.hprel_rhs in
    let rhs_args_w_aliases = List.concat (List.map (fun arg ->
      try List.find (fun svl -> mem arg svl) aliases
      with _ -> [arg]) rhs_args) in 
    let dangling_args = List.filter CP.is_node_typ (diff (* (diff lhs_args lhs_nodes) *) lhs_args rhs_args_w_aliases) in
    let () = x_tinfo_hp (add_str "Dangling args" !CP.print_svl) dangling_args no_pos in
    let combine_dangling_args f = List.fold_left (fun acc_f dangling_arg ->
        CF.mkStar_combine_heap acc_f (mk_dangling_view_node dangling_arg) CF.Flow_combine no_pos
      ) f dangling_args in
    if is_empty dangling_args then hpr, false
    else
      { hpr with hprel_rhs = combine_dangling_args hpr.hprel_rhs }, true

let add_dangling_hprel prog (hpr: CF.hprel) = 
  let pr = Cprinter.string_of_hprel_short in
  Debug.no_1 "Syn:add_dangling_hprel" pr (pr_pair pr string_of_bool) (add_dangling_hprel prog) hpr

let add_dangling_hprel_list prog (hpr_list: CF.hprel list) =
  let n_hpr_list, has_dangling_vars = List.split (List.map (x_add add_dangling_hprel prog) hpr_list) in
  let has_dangling_vars = or_list has_dangling_vars in
  let prog =
    if has_dangling_vars then
      { prog with Cast.prog_view_decls = prog.Cast.prog_view_decls @ [mk_dangling_view_prim]; }
    else prog
  in
  n_hpr_list
  
(*******************)
(***** MERGING *****)
(*******************)
let partition_hprel_list hprels = 
  partition_by_key (fun hpr -> name_of_hprel hpr) CP.eq_spec_var hprels

let rename_hprel_args n_args hprel =
  let hprel_name, hprel_args = sig_of_hprel hprel in
  try
    let sst = List.combine hprel_args n_args in
    CF.subst_hprel_constr sst hprel 
  with _ -> failwith ("Mismatch number of arguments of " ^ (!CP.print_sv hprel_name))

let rename_hprel_list hprels = 
  match hprels with
  | [] -> []
  | hpr::hprs -> 
    let n_args = args_of_hprel hpr in
    hpr::(List.map (rename_hprel_args n_args) hprs)

let cond_of_pre_hprel (hprel: CF.hprel) = 
  let _, lhs_p, _, _, _, _ = x_add_1 CF.split_components hprel.hprel_lhs in
  match hprel.hprel_guard with
  | None -> MCP.pure_of_mix lhs_p
  | Some g -> 
    let _, g_p, _, _, _, _ = x_add_1 CF.split_components g in
    CP.mkAnd (MCP.pure_of_mix lhs_p) (MCP.pure_of_mix g_p) no_pos

let cond_guard_of_pre_hprel cond_list hprel_cond =
  let all_cond_guard = List.find_all (fun c -> imply hprel_cond c) cond_list in
  let cond_guard = CP.join_conjunctions all_cond_guard in
  cond_guard

let transform_pre_hprel_w_cond_guard cond_guard (hprel: CF.hprel) =
  let f_m_f m_f =
    let p_f = MCP.pure_of_mix m_f in
    let gist_p_f = Tpdispatcher.om_gist p_f cond_guard in
    MCP.mix_of_pure gist_p_f
  in
  { hprel with
    hprel_lhs = trans_pure_formula f_m_f hprel.hprel_lhs;
    hprel_guard = map_opt (trans_pure_formula f_m_f) hprel.hprel_guard; }

let transform_pre_hprel_w_cond_guard cond_guard (hprel: CF.hprel) =
  let pr1 = !CP.print_formula in
  let pr2 = Cprinter.string_of_hprel_short in
  Debug.no_2 "transform_pre_hprel_w_cond_guard" pr1 pr2 pr2 
    transform_pre_hprel_w_cond_guard cond_guard hprel

let should_merge_pre_hprels prog hprels = 
  match hprels with
  | []
  | _ ::[] -> false
  | hpr::hprs ->
    let args = args_of_hprel hpr in
    let ex_hpr_lhs = push_exists_for_args hpr.CF.hprel_lhs args in
    List.for_all (fun hp ->
      let ex_hp_lhs = push_exists_for_args hp.CF.hprel_lhs args in
      let equiv_lhs () = 
        (heap_entail_exact_formula prog ex_hpr_lhs ex_hp_lhs) &&
        (heap_entail_exact_formula prog ex_hp_lhs ex_hpr_lhs)
      in
      let equiv_guard () = 
        match hpr.CF.hprel_guard, hp.CF.hprel_guard with
        | None, None -> true
        | Some gr, Some g ->
          (heap_entail_exact_formula prog g gr) &&
          (heap_entail_exact_formula prog gr g)
        | _ -> false
      in (equiv_lhs ()) && (equiv_guard ())) hprs

let should_pre_merge_hprels prog hprels = 
  let pr = pr_hprel_list in
  Debug.no_1 "should_pre_merge_hprels" pr string_of_bool
    (should_merge_pre_hprels prog) hprels
  
(* hprels have the same name *)
(* (A /\ a -> B) /\ (A /\ !a -> C) --> A -> (B /\ a) \/ (C /\ !a) *)
let merge_pre_hprel_list prog hprels =
  match hprels with
  | []
  | _::[] -> hprels
  | _ ->
    (* if List.exists (fun hpr -> is_None hpr.CF.hprel_guard) hprels then hprels *)
    (* else                                                                      *)
      let hprels = rename_hprel_list hprels in
      let conds = List.map cond_of_pre_hprel hprels in
      let sub_conds = List.concat (List.map CP.split_conjunctions conds) in
      let unsat_core = Smtsolver.get_unsat_core sub_conds in
      if is_empty unsat_core then
        let () = y_winfo_pp "Merging is not performed due to the set of pre-hprels does not have disjoint conditions" in
        hprels
      else
        let cond_guards = List.map (fun c -> cond_guard_of_pre_hprel unsat_core c) conds in
        let cond_guard_hprels = List.combine cond_guards hprels in
        let trans_hprels = List.map (fun (c, hpr) -> transform_pre_hprel_w_cond_guard c hpr) cond_guard_hprels in
        if not (should_merge_pre_hprels prog trans_hprels) then
          let () = y_winfo_pp "Merging is not performed due to the set of pre-hprels does not have identical LHS and/or guards" in
          hprels
        else
          let disj_rhs_list = List.fold_left (fun acc (c, hprel) ->
            let rhs_w_cond = CF.add_pure_formula_to_formula c hprel.CF.hprel_rhs in
            acc @ [rhs_w_cond]) [] cond_guard_hprels in
          let disj_rhs = List.fold_left (fun acc f ->
            CF.mkOr acc f no_pos) (List.hd disj_rhs_list) (List.tl disj_rhs_list) in
          let comb_hpr = List.hd trans_hprels in
          let comb_hpr = { comb_hpr with hprel_rhs = disj_rhs } in
          [comb_hpr]

let merge_pre_hprel_list prog hprels =
  let pr = pr_hprel_list in
  Debug.no_1 "merge_pre_hprel_list" pr pr (merge_pre_hprel_list prog) hprels

(* (A -> C) /\ (B -> C) --> (A \/ B) -> C *)
let merge_post_hprel_list prog hprels =
  match hprels with
  | []
  | _::[] -> hprels
  | _ ->
    let hprels = rename_hprel_list hprels in
    let disj_lhs_list = List.map (fun hpr -> hpr.CF.hprel_lhs) hprels in
    let disj_lhs = List.fold_left (fun acc f ->
        CF.mkOr acc f no_pos) (List.hd disj_lhs_list) (List.tl disj_lhs_list) in
    let comb_hpr = List.hd hprels in
    let comb_hpr = { comb_hpr with hprel_lhs = disj_lhs } in
    [comb_hpr]

let merge_post_hprel_list prog hprels =
  let pr = pr_hprel_list in
  Debug.no_1 "merge_post_hprel_list" pr pr (merge_post_hprel_list prog) hprels

let merge_hprel_list prog hprels = 
  let pre_hprels, post_hprels = List.partition is_pre_hprel hprels in
  (merge_pre_hprel_list prog pre_hprels) @
  (merge_post_hprel_list prog post_hprels)

let merge_hprel_list prog hprels =
  let pr = pr_hprel_list in
  Debug.no_1 "Syn:merging" pr pr (merge_hprel_list prog) hprels

let merging prog hprels = 
  let hprel_lists = List.map snd (partition_hprel_list hprels) in
  List.concat (List.map (x_add merge_hprel_list prog) hprel_lists)

(*********************)
(***** UNFOLDING *****)
(*********************)
let hprel_num = ref 0

let fresh_hprel_num () =
  hprel_num := !hprel_num + 1;
  !hprel_num

type hprel_id = {
  hprel_constr: CF.hprel;
  hprel_id: int;
}

let mk_hprel_id hpr = 
  { hprel_constr = hpr; hprel_id = fresh_hprel_num (); }

let partition_hprel_id_list hprel_ids = 
  partition_by_key (fun hpri -> name_of_hprel hpri.hprel_constr) CP.eq_spec_var hprel_ids

let add_back_hrel prog ctx hrel = 
  let hrel_f = CF.mkBase_simp hrel (MCP.mkMTrue no_pos) in
  combine_Star prog ctx hrel_f

let unfolding_one_hrel_def prog ctx hrel (hrel_def: CF.hprel) =
  let pos = no_pos in
  let hrel_name, hrel_args = sig_of_hrel hrel in
  let hprel_rhs_fv = CF.fv hrel_def.hprel_rhs in
  (* Prevent self-recursive pred to avoid infinite unfolding *)
  if mem hrel_name hprel_rhs_fv then
    let () = y_tinfo_pp (
      "WARNING: Unfolding self-recursive predicate " ^ 
      (!CF.print_h_formula hrel) ^ " is not allowed to avoid possibly infinite unfolding!")
    in
    None
  else
    let hrd_lhs = hrel_def.hprel_lhs in
    (* let _, lhs_p, _, _, _, _ = x_add_1 CF.split_components hrd_lhs in *)
    let lhs_p, _, _ = CVU.xpure_sym prog hrd_lhs in
    let lhs_p = MCP.pure_of_mix lhs_p in
    let ex_lhs_p = MCP.mix_of_pure (simplify lhs_p hrel_args) in
    let hrd_guard = hrel_def.hprel_guard in
    let guard_f = 
      match hrd_guard with
      | None -> CF.mkBase_simp HEmp (MCP.mkMTrue pos)
      | Some g -> g
    in
    let guard_h, guard_p, _, _, _, _ = x_add_1 CF.split_components guard_f in
    let guard_h_f = CF.mkBase_simp guard_h ex_lhs_p in
    let rs, residue = x_add heap_entail_formula prog ctx guard_h_f in
    if rs then
      (* let _, ctx_p, _, _, _, _ = x_add_1 CF.split_components ctx in *)
      let ctx_p, _, _ = CVU.xpure_sym prog ctx in
      if is_sat (MCP.merge_mems ctx_p guard_p true) then
        let comb_f = x_add combine_Star prog guard_f residue in
        Some (x_add combine_Star prog comb_f hrel_def.hprel_rhs)
      else None
    else None

let unfolding_one_hrel_def prog ctx hrel (hrel_def: CF.hprel) =
  let pr1 = !CF.print_formula in
  let pr2 = Cprinter.string_of_hprel_short in
  Debug.no_2 "Syn:unfolding_one_hrel_def" pr1 pr2 (pr_option pr1)
    (fun _ _ -> unfolding_one_hrel_def prog ctx hrel hrel_def) ctx hrel_def

let unfolding_one_hrel prog ctx hrel hrel_defs = 
  let hrel_name, hrel_args = sig_of_hrel hrel in
  let merged_hrel_defs = (* x_add merge_hprel_list prog *) hrel_defs in
  let subst_hrel_defs = List.map (
    fun hprel ->
      try
        let sst = List.combine (args_of_hprel hprel) hrel_args in
        CF.subst_hprel_constr sst hprel 
      with _ -> failwith ("Mismatch number of arguments of " ^ (!CP.print_sv hrel_name))
    ) merged_hrel_defs
  in
  let guarded_hrel_defs, unguarded_hrel_defs = List.partition (fun hrel_def ->
      match hrel_def.CF.hprel_guard with Some _ -> true | None -> false) subst_hrel_defs in
  let non_inst_unguarded_hrel_defs, unguarded_hrel_defs = List.partition (is_non_inst_hprel prog) unguarded_hrel_defs in
  (* Only unfolding guarded hrel or non-inst hrel *)
  let unfolding_ctx_list = List.fold_left (fun acc hrel_def ->
      let unfolding_ctx = x_add unfolding_one_hrel_def prog ctx hrel hrel_def in
      match unfolding_ctx with
      | None -> acc
      | Some ctx -> acc @ [ctx]) [] (guarded_hrel_defs @ non_inst_unguarded_hrel_defs)
  in
  let unfolding_ctx_list = 
    if is_empty unguarded_hrel_defs 
    then unfolding_ctx_list
    else unfolding_ctx_list @ [add_back_hrel prog ctx hrel]
  in
  if is_empty unfolding_ctx_list then
    [add_back_hrel prog ctx hrel]
  else unfolding_ctx_list

let folding_one_hrel_def prog ctx hrel (hrel_def: CF.hprel) =
  let pos = no_pos in
  let hrd_lhs = hrel_def.hprel_lhs in
  let hrel_name, hrel_args = sig_of_hrel hrel in
  (* Prevent self-recursive pred to avoid infinite folding *)
  let hprel_lhs_fv = CF.fv hrd_lhs in
  if mem hrel_name hprel_lhs_fv then
    let () = y_binfo_pp (
      "WARNING: Folding self-recursive predicate " ^
      (!CF.print_h_formula hrel) ^ " is prohibited to avoid possibly infinite folding!")
    in
    None
  else
    (* let _, lhs_p, _, _, _, _ = x_add_1 CF.split_components hrd_lhs in *)
    let lhs_p, _, _ = x_add CVU.xpure_sym prog hrd_lhs in
    let lhs_p = MCP.pure_of_mix lhs_p in
    let ex_lhs_p = simplify lhs_p hrel_args in
    let hrd_guard = hrel_def.hprel_guard in
    let guard_f = 
      let b = CF.mkBase_simp HEmp (MCP.mkMTrue pos) in
      match hrd_guard with
      | None -> b
      | Some g -> b (* g *) (* Ignore guard in a post-hprel *)
    in
    let guard_f = CF.add_pure_formula_to_formula ex_lhs_p guard_f in
    let rs, residue = x_add heap_entail_formula prog ctx guard_f in
    if rs then
        let comb_f = x_add combine_Star prog guard_f residue in
        Some (x_add combine_Star prog comb_f hrel_def.hprel_lhs)
    else None

let folding_one_hrel prog ctx hrel hrel_defs = 
  let hrel_name, hrel_args = sig_of_hrel hrel in
  let subst_hrel_defs = List.map (
    fun hprel ->
      try
        let sst = List.combine (args_of_hprel hprel) hrel_args in
        CF.subst_hprel_constr sst hprel 
      with _ -> failwith ("Mismatch number of arguments of " ^ (!CP.print_sv hrel_name))
    ) hrel_defs
  in
 let folding_ctx_list = List.fold_left (fun acc hrel_def ->
      let folding_ctx = x_add folding_one_hrel_def prog ctx hrel hrel_def in
      match folding_ctx with
      | None -> acc
      | Some ctx -> acc @ [ctx]) [] subst_hrel_defs
  in
  if is_empty folding_ctx_list then
    [add_back_hrel prog ctx hrel]
  else folding_ctx_list

let process_one_hrel prog is_unfolding ctx hprel_name hrel hprel_groups =
  let pos = no_pos in
  let hrel_name, hrel_args = sig_of_hrel hrel in
  if CP.eq_spec_var hprel_name hrel_name then
    [add_back_hrel prog ctx hrel]
  else
    let hrel_defs = List.filter (fun (hpr_sv, _) -> 
        CP.eq_spec_var hpr_sv hrel_name) hprel_groups in
    let hrel_defs = List.concat (List.map snd hrel_defs) in
    if is_empty hrel_defs then [add_back_hrel prog ctx hrel]
    else if is_unfolding then (* UNFOLDING FOR PRE-HPREL *)
      unfolding_one_hrel prog ctx hrel hrel_defs
    else (* FOLDING FOR POST-HPREL *)
      folding_one_hrel prog ctx hrel hrel_defs

let process_one_hrel prog is_unfolding ctx hprel_name hrel hprel_groups =
  let pr1 = !CF.print_formula in
  let pr2 = !CF.print_h_formula in
  Debug.no_2 "Syn:process_one_hrel" pr1 pr2 (pr_list pr1)
    (fun _ _ -> process_one_hrel prog is_unfolding ctx hprel_name hrel hprel_groups) 
    ctx hrel

let unfolding_hrel_list prog is_unfolding ctx hprel_name hrel_list hprel_groups =
  let rec helper ctx hrel_list = 
    match hrel_list with
    | [] -> [ctx]
    | hr::hrl ->
      let ctx_list = x_add process_one_hrel prog is_unfolding ctx hprel_name hr hprel_groups in
      List.concat (List.map (fun ctx -> helper ctx hrl) ctx_list)
  in
  let non_inst_hrel_list, norm_hrel_list = List.partition (is_non_inst_hrel prog) hrel_list in
  helper ctx (norm_hrel_list @ non_inst_hrel_list)

let unfolding_hrel_list prog is_unfolding ctx hprel_name hrel_list hprel_groups =
  let pr1 = !CF.print_formula in
  let pr2 = pr_list !CF.print_h_formula in
  Debug.no_2 "Syn:unfolding_hrel_list" pr1 pr2 (pr_list pr1)
    (fun _ _ -> unfolding_hrel_list prog is_unfolding ctx hprel_name hrel_list hprel_groups) 
    ctx hrel_list

let unfolding_hprel_base prog is_unfolding hprel_groups hprel_name f_h f_p =
  let f_hrels, f_hpreds = List.partition CF.is_hrel (CF.split_star_conjunctions f_h) in
  let ctx = CF.mkBase_simp (CF.join_star_conjunctions f_hpreds) f_p in
  let unfolding_ctx_list = x_add unfolding_hrel_list prog is_unfolding ctx hprel_name f_hrels hprel_groups in
  unfolding_ctx_list

let rec unfolding_hprel_formula prog is_unfolding hprel_groups hprel_name (f: CF.formula) =
  match f with 
  | CF.Base { 
      formula_base_heap = h; 
      formula_base_pure = p; } ->
    unfolding_hprel_base prog is_unfolding hprel_groups hprel_name h p
  | CF.Exists { 
      formula_exists_qvars = svl;
      formula_exists_heap = h;
      formula_exists_pure = p } ->
    let unfolding_f_list = unfolding_hprel_base prog is_unfolding hprel_groups hprel_name h p in
    List.map (CF.push_exists svl) unfolding_f_list
  | CF.Or {
      formula_or_f1 = f1;
      formula_or_f2 = f2;
      formula_or_pos = pos; } ->
    let unfolding_f1_list = unfolding_hprel_formula prog is_unfolding hprel_groups hprel_name f1 in
    let unfolding_f2_list = unfolding_hprel_formula prog is_unfolding hprel_groups hprel_name f2 in
    List.concat (List.map (fun f1 -> List.map (fun f2 -> CF.mkOr f1 f2 pos) unfolding_f2_list) unfolding_f1_list)

let unfolding_hprel_formula prog is_unfolding hprel_groups hprel_name (f: CF.formula) =
  let pr = !CF.print_formula in
  Debug.no_1 "unfolding_hprel_formula" pr (pr_list pr)
    (fun _ -> unfolding_hprel_formula prog is_unfolding hprel_groups hprel_name f) f

let unfolding_hprel prog hprel_groups (hpr: CF.hprel): CF.hprel list =
  let hpr_name, hpr_args = sig_of_hprel hpr in
  let is_unfolding = is_pre_hprel hpr in
  let hpr_f = if is_unfolding then hpr.hprel_rhs else hpr.hprel_lhs in
  let unfolding_ctx_list = x_add unfolding_hprel_formula prog is_unfolding hprel_groups hpr_name hpr_f in
    let unfolding_hpr_list = List.map (fun unfolding_f ->
        if is_unfolding then { hpr with hprel_rhs = unfolding_f }
        else { hpr with hprel_lhs = unfolding_f }) unfolding_ctx_list in
    unfolding_hpr_list
    
let unfolding_hprel prog hprel_groups (hpr: CF.hprel): CF.hprel list =
  let pr = Cprinter.string_of_hprel_short in
  Debug.no_1 "Syn:unfolding_hprel" pr (pr_list pr)
    (fun _ -> unfolding_hprel prog hprel_groups hpr) hpr

let rec update_hprel_id_groups hprel_id hprel_sv hprel_id_list hprel_id_groups =
  match hprel_id_groups with
  | [] -> []
  | (hpr_sv, hpri_group)::hpri_groups ->
    if CP.eq_spec_var hpr_sv hprel_sv then
      let replaced_hpri_group = 
        hprel_id_list @ 
        (List.filter (fun hpri -> hpri.hprel_id != hprel_id) hpri_group) 
      in
      (hpr_sv, replaced_hpri_group)::hpri_groups
    else 
      (hpr_sv, hpri_group)::(update_hprel_id_groups hprel_id hprel_sv hprel_id_list hpri_groups)

let rec helper_unfolding_hprel_list prog hprel_id_groups hprel_id_list =
  match hprel_id_list with
  | [] -> []
  | hpri::hpril ->
    let hprel_groups = List.map (fun (hprel_sv, hprel_id_list) ->
        (hprel_sv, List.map (fun hpri -> hpri.hprel_constr) hprel_id_list)
      ) hprel_id_groups in
    let unfolding_hpr = x_add unfolding_hprel prog hprel_groups hpri.hprel_constr in
    let unfolding_hpri = List.map mk_hprel_id unfolding_hpr in
    let updated_hprel_id_groups = update_hprel_id_groups 
      hpri.hprel_id (name_of_hprel hpri.hprel_constr) unfolding_hpri hprel_id_groups in
    unfolding_hpr @ (helper_unfolding_hprel_list prog updated_hprel_id_groups hpril)

let helper_unfolding_hprel_list prog hprel_id_groups hprel_id_list =
  let pr1 = pr_hprel_list in
  let pr2 hpril = pr1 (List.map (fun hpri -> hpri.hprel_constr) hpril) in
  let pr3 = pr_list (pr_pair !CP.print_sv pr2) in
  Debug.no_2 "Syn:helper_unfolding_hprel_list" pr2 pr3 pr1
    (fun _ _ -> helper_unfolding_hprel_list prog hprel_id_groups hprel_id_list)
    hprel_id_list hprel_id_groups

let unfolding_hprel_list prog hprel_list =
  let sorted_hprel_list = sort_hprel_list hprel_list in
  let hprel_id_list = List.map mk_hprel_id sorted_hprel_list in
  let hprel_id_groups = partition_hprel_id_list hprel_id_list in
  x_add helper_unfolding_hprel_list prog hprel_id_groups hprel_id_list

let selective_unfolding prog other_hprels hprels = 
  let sorted_hprel_list = sort_hprel_list (hprels @ other_hprels) in
  let hprel_names = List.map name_of_hprel hprels in
  let sorted_selective_hprel_list = List.filter (fun s_hpr ->
      mem (name_of_hprel s_hpr) hprel_names) sorted_hprel_list in
  let hprel_id_list = List.map mk_hprel_id sorted_selective_hprel_list in
  let other_hprel_id_list = List.map mk_hprel_id other_hprels in
  let hprel_id_groups = partition_hprel_id_list (hprel_id_list @ other_hprel_id_list) in 
  x_add helper_unfolding_hprel_list prog hprel_id_groups hprel_id_list

let selective_unfolding prog other_hprels hprels = 
  let pr = pr_hprel_list in
  Debug.no_2 "Syn:selective_unfolding" pr pr pr 
    (fun _ _ -> selective_unfolding prog other_hprels hprels) other_hprels hprels

let unfolding prog hprels = 
  unfolding_hprel_list prog hprels

let unfolding prog hprels = 
  let pr = pr_hprel_list in
  Debug.no_1 "Syn:unfolding" pr pr (fun _ -> unfolding prog hprels) hprels

(**************************)
(***** PARAMETERIZING *****)
(**************************)
let remove_dangling_heap_formula (f: CF.formula) = 
  let f_h_f _ hf = 
    match hf with
    | CF.ViewNode ({ 
        h_formula_view_node = view_node;
        h_formula_view_name = view_name; } as v) ->
      if eq_id view_name dangling_view_name then
        Some (CF.HEmp, [view_node])
      else Some (hf, [])
    | _ -> None
  in
  trans_heap_formula f_h_f f

let remove_dangling_heap_formula (f: CF.formula) = 
  let pr1 = !CF.print_formula in
  let pr2 = !CP.print_svl in
  Debug.no_1 "Syn:remove_dangling_heap_formula" pr1 (pr_pair pr1 pr2)
    remove_dangling_heap_formula f
  
let add_dangling_params hrel_name dangling_params (f: CF.formula) = 
  let f_h_f _ hf = 
    match hf with
    | CF.HRel (hr_sv, hr_args, hr_pos) ->
      if CP.eq_spec_var hr_sv hrel_name then
        let parameterized_hrel = CF.HRel (hr_sv, hr_args @ dangling_params, hr_pos) in
        Some (parameterized_hrel, [])
      else Some (hf, [])
    | _ -> None
  in
  fst (trans_heap_formula f_h_f f)

let add_dangling_params hrel_name dangling_params (f: CF.formula) = 
  let pr1 = !CF.print_formula in
  let pr2 = !CP.print_sv in
  let pr3 = pr_list !CP.print_exp in
  Debug.no_3 "Syn:add_dangling_params" pr1 pr2 pr3 pr1
    (fun _ _ _ -> add_dangling_params hrel_name dangling_params f)
    f hrel_name dangling_params

let dangling_parameterizing_hprel (hpr: CF.hprel) =
  let is_pre = is_pre_hprel hpr in
  let f = if is_pre then hpr.hprel_rhs else hpr.hprel_lhs in 
  let f_disjs = CF.list_of_disjuncts f in
  let n_f_disjs_w_dangling_vars = List.fold_left (fun acc disj ->
    let n_disj, dangling_vars = x_add_1 remove_dangling_heap_formula disj in
    acc @ [(n_disj, dangling_vars)]) [] f_disjs
  in
  let all_dangling_vars = List.concat (List.map snd n_f_disjs_w_dangling_vars) in
  if is_empty all_dangling_vars then hpr, idf
  else
    let n_f_disjs, dangling_params_lists = List.split (List.map (fun (disj, dangling_vars) ->
      let fresh_dangling_vars = CP.fresh_spec_vars dangling_vars in
      let dangling_params = List.map (fun dv -> CP.mkVar dv no_pos) fresh_dangling_vars in
      let n_disj = CF.subst (List.combine dangling_vars fresh_dangling_vars) disj in
      (n_disj, dangling_params)) n_f_disjs_w_dangling_vars)
    in
    let n_f_opt = CF.join_conjunct_opt n_f_disjs in
    match n_f_opt with
    | None -> hpr, idf
    | Some n_f ->
      let dangling_params = List.concat dangling_params_lists in
      let hpr_name = name_of_hprel hpr in
      let f_update_params_hprel hpr =
        { hpr with
          CF.hprel_lhs = x_add add_dangling_params hpr_name dangling_params hpr.CF.hprel_lhs;
          CF.hprel_rhs = x_add add_dangling_params hpr_name dangling_params hpr.CF.hprel_rhs;
        }
      in
      let f_update_params_hprel hpr =
        let pr = Cprinter.string_of_hprel_short in
        Debug.no_1 "f_update_params_hprel" pr pr f_update_params_hprel hpr
      in
      let n_hpr = 
        if is_pre then { hpr with hprel_rhs = n_f }
        else { hpr with hprel_lhs = n_f }
      in 
      n_hpr, f_update_params_hprel

let dangling_parameterizing_hprel (hpr: CF.hprel) =
  let pr1 = Cprinter.string_of_hprel_short in
  let pr2 = fun (hpr, _) -> pr1 hpr in
  Debug.no_1 "Syn:dangling_parameterizing_hprel" pr1 pr2 dangling_parameterizing_hprel hpr

let rec dangling_parameterizing hprels =
  let rec helper_x acc hprels = 
    match hprels with
    | [] -> acc
    | hpr::hprl ->
      let hpr_wo_dangling, f_update_params = x_add_1 dangling_parameterizing_hprel hpr in
      let n_hpr = f_update_params hpr_wo_dangling in
      let n_hprl = List.map f_update_params hprl in
      let n_acc = List.map f_update_params acc in
      helper (n_acc @ [n_hpr]) n_hprl

  and helper acc hprels =
    let pr = pr_hprel_list in
    Debug.no_2 "dangling_parameterizing_helper" pr pr pr
      helper_x acc hprels
  in
  
  helper [] hprels

let dangling_parameterizing hprels = 
  let pr = pr_hprel_list in
  Debug.no_1 "Syn:parameterizing" pr pr 
    (fun _ -> dangling_parameterizing hprels) hprels

(***********************************)
(***** TRANSFORM HPREL TO VIEW *****)
(***********************************)
let trans_hprel_to_view iprog prog hprels = 
  let hprel_lists = partition_hprel_list hprels in
  let single_hprel_lists, others = List.partition (fun (_, l) -> List.length l == 1) hprel_lists in
  let single_hprel_list = List.map (fun (sv, l) -> (sv, List.hd l)) single_hprel_lists in
  let () =
    if not (is_empty others) then
      let svl = List.map fst others in
      y_binfo_pp ("Cannot transform the hprels of " ^ (!CP.print_svl svl) ^ " into view declarations.")
  in
  let derived_views = 
    List.fold_left (fun acc (sv, hpr) ->
      let vdecls = if !Globals.new_pred_syn then
          let vdecl = view_decl_of_hprel prog hpr in
          [vdecl]
        else Saout.view_decl_of_hprel iprog prog hpr
      in
      (* let () = y_binfo_hp (add_str ("View Decl of " ^ (!CP.print_sv sv)) (pr_list_ln Cprinter.string_of_view_decl_short)) vdecls in *)
      acc @ vdecls) [] single_hprel_list 
  in
  let () = y_tinfo_hp (add_str "derived_views" (pr_list Cprinter.string_of_view_decl_short)) derived_views in
  (* prog_view_decls of iprog and cprog are updated by norm_derived_views *)
  let norm_derived_views = norm_derived_views iprog prog derived_views in
  let () = y_tinfo_hp (add_str "Derived Views" (pr_list Cprinter.string_of_view_decl_short)) norm_derived_views in
  norm_derived_views

let trans_hprel_to_view iprog cprog hprels = 
  let pr1 = Cprinter.string_of_hprel_list_short in
  let pr2 = pr_list Cprinter.string_of_view_decl_short in
  Debug.no_1 "Syn:trans_hprel_to_view" pr1 pr2 
    (fun _ -> trans_hprel_to_view iprog cprog hprels) hprels

(**********************)
(***** PRED REUSE *****)
(**********************)
let aux_pred_reuse iprog cprog all_views =
  let ids = List.map (fun x -> x.Cast.view_name) all_views in 
  (* let vdefs = cprog.Cast.prog_view_decls in *)
  let vdefs = C.get_sorted_view_decls cprog in
  let () = y_binfo_pp "XXX Scheduling pred_elim_useless" in
  let vdefs = Norm.norm_elim_useless vdefs ids in
  let () = y_binfo_pp "XXX Scheduling pred_reuse" in
  let v_ids = List.map (fun x -> x.Cast.view_name) vdefs in
  let () = y_binfo_pp "XXX Scheduling pred_reuse" in
  let () = y_binfo_hp (add_str "XXX derived_view names" (pr_list pr_id)) ids in
  let () = y_tinfo_hp (add_str "XXX derived views" 
      (pr_list Cprinter.string_of_view_decl_short)) all_views in
  let () = y_binfo_hp (add_str "XXX existing view names" (pr_list pr_id)) v_ids in
  let lst = Norm.norm_reuse_rgx iprog cprog vdefs (REGEX_LIST ids) REGEX_STAR in
  let () = y_binfo_hp (add_str "XXX reuse found ..." (pr_list (pr_pair pr_id pr_id))) lst in
  let () = y_binfo_pp "XXX Scheduling pred_reuse_subs" in
  let () = Norm.norm_reuse_subs iprog cprog vdefs ids in
  lst
  
(*************************)
(***** DERIVING VIEW *****)
(*************************)
let derive_view_norm prog other_hprels hprels = 
  (* PRE-PROCESSING *)
  let pre_hprels, post_hprels = List.partition is_pre_hprel hprels in
  let all_hprels = hprels @ other_hprels in
  (* WN : will other_hprels cause a problem later if it is neither unfold or fold? *)
  let () =
    if other_hprels != [] then
      let () = y_tinfo_hp (add_str "other_hprels is non-empty" pr_hprel_list) other_hprels in
      () 
  in
  (* SIMPLIFY *)
  let simplified_all_hprels = simplify_hprel_list all_hprels in
  (* ADD DANGLING *)
  let all_hprels_w_dangling = add_dangling_hprel_list prog simplified_all_hprels in
  let all_pre_hprels, all_post_hprels = List.partition is_pre_hprel all_hprels_w_dangling in
  (* DERIVING PRE: MERGE -> UNFOLD *)
  let all_merged_pre_hprels = merging prog all_pre_hprels in
  let selective_pre_hprel_ids = List.map (fun hpr -> name_of_hprel hpr) pre_hprels in
  let selective_merged_pre_hprels, other_merged_pre_hprels = List.partition 
    (fun hpr -> mem (name_of_hprel hpr) selective_pre_hprel_ids) all_merged_pre_hprels in
  let unfolding_pre_hprels = selective_unfolding prog other_merged_pre_hprels selective_merged_pre_hprels in
  (* DERIVING POST: FOLD -> MERGE *)
  let selective_post_hprel_ids = List.map (fun hpr -> name_of_hprel hpr) post_hprels in
  let selective_merged_post_hprels, other_merged_post_hprels = List.partition 
    (fun hpr -> mem (name_of_hprel hpr) selective_post_hprel_ids) all_post_hprels in
  let folding_post_hprels = selective_unfolding prog other_merged_post_hprels selective_merged_post_hprels in
  let merged_folding_post_hprels = merging prog folding_post_hprels in
  (* PARAM DANGLING *)
  let selective_merged_hprels = dangling_parameterizing (unfolding_pre_hprels @ merged_folding_post_hprels) in
  (* SIMPLIFY *)
  let simplified_selective_hprels = simplify_hprel_list selective_merged_hprels in
  simplified_selective_hprels

let derive_view_norm prog other_hprels hprels = 
  let pr = Cprinter.string_of_hprel_list_short in
  Debug.no_1 "Syn:derive_view_norm" pr pr
    (derive_view_norm prog other_hprels) hprels

let derive_view iprog cprog other_hprels hprels = 
  let hprels = Gen.BList.remove_dups_eq CF.eq_hprel_defn hprels in
  let other_hprels = Gen.BList.remove_dups_eq CF.eq_hprel_defn other_hprels in
  let pr = Cprinter.string_of_hprel_list_short in
  (* let () = y_binfo_hp (add_str "hprels" pr) hprels in *)
  (* let () = y_binfo_hp (add_str "other hprels" pr) other_hprels in *)
  let simplified_selective_hprels = derive_view_norm cprog other_hprels hprels in
  (* DERIVING VIEW *)
  let derived_views = trans_hprel_to_view iprog cprog simplified_selective_hprels in
  (* let derived_views = List.map (fun view -> unfolding_view iprog cprog view) derived_views in *)
  (derived_views, simplified_selective_hprels)

(* type: Saout.I.prog_decl -> *)
(*   Sautil.C.prog_decl -> *)
(*   SynUtils.CF.hprel list -> *)
(*   SynUtils.CF.hprel list -> Rev_ast.C.view_decl list * SynUtils.CF.hprel list *)
let derive_view iprog prog other_hprels hprels = 
  let pr1 = Cprinter.string_of_hprel_list_short in
  let pr2 = pr_list Cprinter.string_of_view_decl_short in
  Debug.no_2 "Syn:derive_view" pr1 pr1 (pr_pair pr2 pr1)
    (derive_view iprog prog) other_hprels hprels

(*******************************************)
(***** ELIM HEAD / TAIL / DISJ OF PRED *****)
(*******************************************)
(* type:                                                     *)
(*   Astsimp.I.prog_decl ->                                  *)
(*   Astsimp.C.prog_decl ->                                  *)
(*   C.view_decl ->                                          *)
(*   Globals.ident list ->                                   *)
(*   Rev_ast.CF.formula -> Rev_ast.CF.formula -> C.view_decl *)
let derive_equiv_view_by_lem ?(tmp_views=[]) iprog cprog view l_ivars l_head l_body =
  let l_name = "lem_inf_" ^ view.C.view_name in
  let l_ihead = Rev_ast.rev_trans_formula l_head in
  let l_ibody = Rev_ast.rev_trans_formula l_body in
  let llemma = I.mk_lemma l_name LEM_INFER LEM_GEN Left l_ivars l_ihead l_ibody in
  let () = llemma.I.coercion_infer_obj # set INF_CLASSIC in (* @classic *)
  let () = llemma.I.coercion_infer_obj # set INF_PURE_FIELD in (* @pure_field *)
  let () = y_tinfo_hp (add_str ("llemma " ^ l_name) Iprinter.string_of_coercion) llemma in 
  
  (* The below method updates CF.sleek_hprel_assumes via lemma proving *)
  let lres, _ = x_add Lemma.manage_infer_lemmas [llemma] iprog cprog in
  if not lres then
    let () = y_binfo_pp "XXX fail infer ---> " in
    let () = restore_view iprog cprog view in
    view
  else
    let () = y_binfo_pp "XXX proven infer ---> " in
    let () = y_binfo_hp (Iprinter.string_of_coercion) llemma in
    let () = List.iter (fun v ->
      let () = C.update_un_struc_formula (trans_hrel_to_view_formula cprog) v in
      let () = C.update_view_formula (trans_hrel_to_view_struc_formula cprog) v in
      let () = C.update_view_decl cprog v in
      let () = I.update_view_decl iprog (Rev_ast.rev_trans_view_decl v) in
      ()) tmp_views in
    (* derived_views have been added into prog_view_decls of iprog and cprog *)
    let derived_views, new_hprels = process_hprel_assumes_res "Deriving Segmented Views" 
        CF.sleek_hprel_assumes snd (REGEX_LIST l_ivars)
        (derive_view iprog cprog) 
    in
    (* let () = y_binfo_pp "XXX Scheduling pred_reuse_subs" in                                     *)
    let all_d_views = tmp_views@derived_views in
    (* let ids = List.map (fun x -> x.Cast.view_name) all_d_views in                               *)
    (* let vdefs = cprog.Cast.prog_view_decls in                                                   *)
    (* let v_ids = List.map (fun x -> x.Cast.view_name) vdefs in                                   *)
    (* let () = y_binfo_hp (add_str "XXX derived_view names" (pr_list pr_id)) ids in               *)
    (* let () = y_binfo_hp (add_str "XXX existing view names" (pr_list pr_id)) v_ids in            *)
    (* let lst = Norm.norm_reuse_rgx iprog cprog vdefs (REGEX_LIST ids) REGEX_STAR in              *)
    (* let () = y_binfo_hp (add_str "XXX reuse found .." (pr_list (pr_pair pr_id pr_id))) lst in   *)
    (* let () = y_tinfo_hp (add_str "derived views" (pr_list Cprinter.string_of_view_decl_short))  *)
    (*     all_d_views in                                                                          *)
    let lst = aux_pred_reuse iprog cprog all_d_views in
    (* Equiv test to form new pred *)
    let r_cbody = trans_hrel_to_view_formula cprog l_body in
    let r_ibody = Rev_ast.rev_trans_formula r_cbody in
    let rlemma = I.mk_lemma (l_name ^ "_rev") LEM_TEST LEM_GEN Right [] l_ihead r_ibody in
    let rres, _ = x_add Lemma.manage_infer_lemmas_x "test" [rlemma] iprog cprog in
    if not rres then 
      let () = y_binfo_pp "XXX fail <--- " in
      let () = y_binfo_hp (Iprinter.string_of_coercion) rlemma in
       let () = restore_view iprog cprog view in
      view
    else
      let () = y_binfo_pp "XXX proven equiv ..." in
      let vbody = CF.set_flow_in_formula_override 
          { CF.formula_flow_interval = !top_flow_int; CF.formula_flow_link = None } 
          r_cbody 
      in
      let self_node = mk_self_node view.C.view_name vbody in
      let () = 
        view.C.view_formula <- CF.formula_to_struc_formula 
            (Typeinfer.case_normalize_renamed_formula iprog (self_node::(elim_useless_vars view.C.view_vars)) [] vbody);
        view.C.view_un_struc_formula <- [(vbody, (fresh_int (), ""))];
        view.C.view_raw_base_case <- None;
        view.C.view_base_case <- None
      in
      let norm_view = norm_single_view iprog cprog view in
      let () = y_binfo_hp (add_str "norm_view" Cprinter.string_of_view_decl_short) norm_view in
      norm_view

(* type:                                                     *)
(*   Astsimp.I.prog_decl ->                                  *)
(*   Astsimp.C.prog_decl ->                                  *)
(*   C.view_decl ->                                          *)
(*   Globals.ident list ->                                   *)
(*   Rev_ast.CF.formula -> Rev_ast.CF.formula -> C.view_decl *)
let derive_equiv_view_by_lem ?(tmp_views=[]) iprog cprog view l_ivars l_head l_body =
  let pr1 = pr_list pr_id in
  let pr2 = !CF.print_formula in
  let pr3 = Cprinter.string_of_view_decl_short in
  Debug.no_3 "Syn:derive_equiv_view_by_lem" pr1 pr2 pr2 pr3
    (fun _ _ _ -> derive_equiv_view_by_lem ~tmp_views:tmp_views iprog cprog view l_ivars l_head l_body) l_ivars l_head l_body

let elim_head_pred iprog cprog pred = 
  let pred_f = C.formula_of_unstruc_view_f pred in
  let self_node = mk_self_node pred.C.view_name pred_f in
  let _, common_node_chain = find_common_node_chain self_node (CF.list_of_disjuncts pred_f) in
  let () = y_tinfo_hp (add_str "Common node chain" (pr_list !CF.print_h_formula)) common_node_chain in
  match common_node_chain with
  | [] -> pred
  | n::ns ->
    let common_heap = List.fold_left (fun acc f -> CF.mkStarH acc f no_pos) n ns in
    let common_f = CF.mkBase_simp common_heap (MCP.mkMTrue no_pos) in
    let args = collect_feasible_heap_args_formula cprog [] common_f in
    let nodes = CF.collect_node_var_formula common_f in
    let dangling_vars = List.filter CP.is_node_typ (diff args nodes) in
    let dangling_vars = remove_dups dangling_vars in
    let () = y_tinfo_hp (add_str "Unknown nodes" !CP.print_svl) dangling_vars in
    let fresh_pred_args = CP.fresh_spec_vars pred.C.view_vars in
    let fresh_pred_I_args = List.map (fun v -> (v, I)) (elim_useless_vars fresh_pred_args) in
    let hrel_list, unknown_vars = List.split (List.map 
        (fun v -> C.add_raw_hp_rel cprog false true ((v, I)::fresh_pred_I_args) no_pos) dangling_vars) in
    let () =  iprog.I.prog_hp_decls <- (List.map Rev_ast.rev_trans_hp_decl cprog.C.prog_hp_decls) in
    let unknown_f = List.fold_left (fun f h -> CF.mkStar_combine_heap f h CF.Flow_combine no_pos) common_f hrel_list in
    let pred_h = CF.mkViewNode self_node pred.C.view_name fresh_pred_args no_pos in
    (* let norm_flow = { CF.formula_flow_interval = exlist # get_hash n_flow; CF.formula_flow_link = None } in *)
    let norm_flow = CF.flow_formula_of_formula unknown_f in
    let pred_f = CF.set_flow_in_formula_override norm_flow (CF.formula_of_heap pred_h no_pos) in
    (* let ex_vars = remove_dups (diff (diff (CF.fv unknown_f) unknown_vars) (CF.fv pred_f)) in *)
    (* let unknown_f = CF.push_exists ex_vars unknown_f in                                      *)

    let ivars = List.map CP.name_of_spec_var unknown_vars in
    x_add derive_equiv_view_by_lem iprog cprog pred ivars pred_f unknown_f

let elim_head_pred iprog cprog pred = 
  let pr = Cprinter.string_of_view_decl_short in
  Debug.no_1 "elim_head_pred" pr pr 
    (fun _ -> elim_head_pred iprog cprog pred) pred

let elim_tail_pred iprog cprog pred = 
  let pred_f = C.formula_of_unstruc_view_f pred in
  let self_node =
    try
      List.find (fun sv -> eq_str (CP.name_of_spec_var sv) Globals.self) (CF.fv pred_f)
    with _ -> CP.SpecVar (Named pred.C.view_name, Globals.self, Unprimed)
  in
  let base_cases = find_pred_base_case pred in
  try
    let node_base_case = List.find (fun f -> 
        not (is_empty (snd (find_heap_node self_node f))) 
      ) base_cases in
    let fresh_pred_args = CP.fresh_spec_vars pred.C.view_vars in
    let fresh_self_node = CP.fresh_spec_var self_node in
    let pred_h = CF.mkViewNode self_node pred.C.view_name fresh_pred_args no_pos in
    let unknown_h, unknown_hpred = C.add_raw_hp_rel cprog false true [(self_node, I); (fresh_self_node, I)] no_pos in
    let () =  iprog.I.prog_hp_decls <- (List.map Rev_ast.rev_trans_hp_decl cprog.C.prog_hp_decls) in
    let unknown_f = CF.mkStar_combine_heap 
        (CF.subst [(self_node, fresh_self_node)] node_base_case) 
        unknown_h CF.Flow_combine no_pos in
    let norm_flow = CF.flow_formula_of_formula unknown_f in
    let pred_f = CF.set_flow_in_formula_override norm_flow (CF.formula_of_heap pred_h no_pos) in
    x_add derive_equiv_view_by_lem iprog cprog pred [CP.name_of_spec_var unknown_hpred] pred_f unknown_f
  with _ -> pred

let elim_tail_pred iprog cprog pred = 
  let pr = Cprinter.string_of_view_decl_short in
  Debug.no_1 "elim_tail_pred" pr pr 
    (fun _ -> elim_tail_pred iprog cprog pred) pred

let rec norm_pred_list f_norm preds = 
  (* List.map (elim_head_pred iprog cprog) preds *)
  match preds with
  | [] -> []
  | p::ps ->
    let lazy_ps = lazy (norm_pred_list f_norm ps) in
    try
      let n_p = f_norm p in
      n_p::(Lazy.force lazy_ps)
    with e ->
      let () = y_binfo_pp (Printexc.to_string e) in
      let () = report_warning no_pos ("Cannot normalize the view " ^ p.C.view_name) in
      Lazy.force lazy_ps

let elim_head_pred_list iprog cprog preds =
  norm_pred_list (elim_head_pred iprog cprog) preds

let elim_tail_pred_list iprog cprog preds =
  norm_pred_list (elim_tail_pred iprog cprog) preds

(*********************)
(***** PRED EXTN *****)
(*********************)

let extn_norm_pred iprog cprog extn_pred norm_pred =
  let norm_ipred = I.look_up_view_def_raw 21 iprog.I.prog_view_decls norm_pred.C.view_name in
  let extn_view_name = "extn_" ^ norm_ipred.I.view_name in
  let extn_view_var = extn_pred.C.view_name ^ "_prop" in
  let extn_iview = I.mk_iview_decl ~v_kind:View_DERV extn_view_name "" 
      (norm_ipred.I.view_vars @ [extn_view_var])
      (IF.mkETrue top_flow no_pos) no_pos
  in
  let orig_info = (norm_ipred.I.view_name, norm_ipred.I.view_vars) in
  (* TODO: Auto derive REC *)
  let extn_info = (extn_pred.C.view_name, ["REC"], [extn_view_var]) in
  let extn_iview = { extn_iview with 
    I.view_derv_info = [(orig_info, extn_info)];
    I.view_derv_extns = [extn_info] } in
  let extn_cview_lst = x_add Derive.trans_view_dervs iprog 
    Rev_ast.rev_trans_formula Astsimp.trans_view [] 
    cprog.C.prog_view_decls extn_iview in
  let () = y_winfo_pp "Chanh, Losing some cviews here .." in
  let extn_cview = List.hd extn_cview_lst in
  let extn_cview = { extn_cview with C.view_name = norm_pred.C.view_name } in
  let () = C.update_view_decl cprog extn_cview in
  extn_cview

let extn_norm_pred_list iprog cprog extn_pred norm_preds = 
  List.map (fun pred -> extn_norm_pred iprog cprog extn_pred pred) norm_preds

let extn_pred_list iprog cprog extn preds =
  try
    let extn_pred = C.look_up_view_def_raw 20 cprog.C.prog_view_decls extn in
    match extn_pred.C.view_kind with
    | View_EXTN -> 
      let norm_preds = List.fold_left (fun acc pred ->
        match pred.C.view_kind with
        | View_NORM -> acc @ [pred]
        | k -> 
          let () = report_warning no_pos (
            "Cannot extend the " ^ (string_of_view_kind k) ^
            " " ^ pred.C.view_name)
          in acc) [] preds 
      in
      extn_norm_pred_list iprog cprog extn_pred norm_preds
    | _ -> failwith (extn ^ " is not a View_EXTN")
  with Not_found -> failwith ("Cannot find the View_EXTN " ^ extn)

let extn_pred_id_list iprog cprog extn preds =
  let pred_decls = List.map (fun id ->
    try C.look_up_view_def_raw 21 cprog.C.prog_view_decls id
    with _ -> failwith ("Cannot find the view " ^ id)) preds in
  extn_pred_list iprog cprog extn pred_decls

let extn_pred_scc iprog cprog scc_proc_names = 
  let scc_procs = List.map (fun proc_name ->
    let proc = C.look_up_proc_def_raw cprog.C.new_proc_decls proc_name in
    proc) scc_proc_names in
  let scc_proc_specs = List.map (fun proc -> 
    proc.C.proc_stk_of_static_specs # top) scc_procs in
  let extn_lst = merge_infer_extn_lsts 
      (List.map get_inf_pred_extn_struc_formula scc_proc_specs) in
  let extn_pred_lst = partition_by_key 
    (fun (_, prop) -> prop) eq_str
    (expand_infer_extn_lst extn_lst) in
  List.map (fun (extn, extn_pred_lst) ->
    let preds = List.map (fun (id, _) -> id) extn_pred_lst in
    extn_pred_id_list iprog cprog extn preds) extn_pred_lst

(*********************************)
(***** COMBINE DISJ BRANCHES *****)
(*********************************)
let unify_disj_pred iprog cprog pred = 
  let pred_f = C.formula_of_unstruc_view_f pred in
  let self_node = mk_self_node pred.C.view_name pred_f in
  let common_node_chain, other_branches = find_common_node_chain_branches self_node (CF.list_of_disjuncts pred_f) in
  let () = y_tinfo_hp (add_str "Common node chain" (pr_list !CF.print_h_formula)) common_node_chain in
  match common_node_chain with
  | [] -> pred
  | n::ns ->
    let common_heap = List.fold_left (fun acc f -> CF.mkStarH acc f no_pos) n ns in
    let common_f = CF.mkBase_simp common_heap (MCP.mkMTrue no_pos) in
    let args = collect_feasible_heap_args_formula cprog [] common_f in
    let nodes = CF.collect_node_var_formula common_f in
    let dangling_vars = List.filter CP.is_node_typ (diff args nodes) in
    let dangling_vars = remove_dups dangling_vars in
    let () = y_tinfo_hp (add_str "Dangling nodes" !CP.print_svl) dangling_vars in
    let pred_I_args = List.map (fun v -> (v, I)) (elim_useless_vars pred.C.view_vars) in
    let hrel_list, unknown_vars = List.split (List.map 
        (fun v -> C.add_raw_hp_rel cprog false true ((v, I)::pred_I_args) no_pos) dangling_vars) in
    let () =  iprog.I.prog_hp_decls <- (List.map Rev_ast.rev_trans_hp_decl cprog.C.prog_hp_decls) in
    let unknown_branches = List.fold_left (fun f h -> CF.mkStar_combine_heap f h CF.Flow_combine no_pos) common_f hrel_list in
    let vbody = CF.formula_of_disjuncts (other_branches @ [unknown_branches]) in
    let vbody = CF.set_flow_in_formula_override 
        { CF.formula_flow_interval = !top_flow_int; CF.formula_flow_link = None } 
        vbody 
    in
    let vbody = Typeinfer.case_normalize_renamed_formula iprog (self_node::(elim_useless_vars pred.C.view_vars)) [] vbody in
    
    (* Construct a new view with unknown HeapPred *)
    let tmp_name = "tmp_" ^ pred.C.view_name in
    let tmp_cpred = { pred with
      C.view_name = tmp_name;
      C.view_formula = CF.formula_to_struc_formula vbody;
      C.view_un_struc_formula = [(vbody, (fresh_int (), ""))]; } 
    in
    (* let tmp_ipred = Rev_ast.rev_trans_view_decl tmp_cpred in *)
    (* let () = C.update_view_decl cprog tmp_cpred in           *)
    (* let () = I.update_view_decl iprog tmp_ipred in           *)
    let norm_tmp_cpred = norm_single_view iprog cprog tmp_cpred in 
    let tmp_v = [norm_tmp_cpred] in
    let () = y_binfo_hp (add_str "new view_decls" (pr_list Cprinter.string_of_view_decl_short)) tmp_v in
        (* cprog.C.prog_view_decls *) 
    let fresh_pred_args = CP.fresh_spec_vars pred.C.view_vars in
    let norm_flow = CF.flow_formula_of_formula unknown_branches in
    let pred_h = CF.mkViewNode self_node pred.C.view_name fresh_pred_args no_pos in
    let pred_f = CF.set_flow_in_formula_override norm_flow (CF.formula_of_heap pred_h no_pos) in
    let tmp_pred_h = CF.mkViewNode self_node tmp_name fresh_pred_args no_pos in
    let tmp_pred_f = CF.set_flow_in_formula_override norm_flow (CF.formula_of_heap tmp_pred_h no_pos) in
    let ivars = List.map CP.name_of_spec_var unknown_vars in
    x_add (derive_equiv_view_by_lem ~tmp_views:tmp_v) iprog cprog pred ivars pred_f tmp_pred_f

let unify_disj_pred_list iprog cprog preds =
  norm_pred_list (unify_disj_pred iprog cprog) preds

(****************)
(***** MAIN *****)
(****************)
let syn_pre_preds prog (is: CF.infer_state) = 
  if !Globals.new_pred_syn then
    let () = x_binfo_pp ">>>>> Step 0: Simplification <<<<<" no_pos in
    let is_all_constrs = CF.add_infer_type_to_hprel is.CF.is_all_constrs in
    let is_all_constrs = simplify_hprel_list is_all_constrs in
    let () = x_tinfo_hp (add_str "Simplified hprels" 
        pr_hprel_list) is_all_constrs no_pos
    in
  
    let () = x_binfo_pp ">>>>> Step 1: Adding dangling references <<<<<" no_pos in
    let is_all_constrs = x_add add_dangling_hprel_list prog is_all_constrs in
    (* let is_all_constrs, has_dangling_vars = List.split (List.map (x_add add_dangling_hprel prog) is_all_constrs) in *)
    (* let has_dangling_vars = or_list has_dangling_vars in                                                            *)
    (* let prog =                                                                                                      *)
    (*   if has_dangling_vars then                                                                                     *)
    (*     { prog with Cast.prog_view_decls = prog.Cast.prog_view_decls @ [mk_dangling_view_prim]; }                   *)
    (*   else prog                                                                                                     *)
    (* in                                                                                                              *)
    (* let () =                                                                                                        *)
    (*   if has_dangling_vars then                                                                                     *)
    (*     x_tinfo_hp (add_str "Detected dangling vars"                                                                *)
    (*         pr_hprel_list) is_all_constrs no_pos                                                                    *)
    (*   else x_tinfo_pp "No dangling var is detected" no_pos                                                          *)
    (* in                                                                                                              *)

    (* let () = x_binfo_pp ">>>>> Step 2A: Merging <<<<<" no_pos in   *)
    (* let is_all_constrs = x_add merging prog is_all_constrs in      *)
    (* let () = x_binfo_hp (add_str "Merging result"                  *)
    (*     pr_hprel_list) is_all_constrs no_pos *)
    (* in                                                             *)
  
    let () = x_binfo_pp ">>>>> Step 2: Unfolding <<<<<" no_pos in
    let is_all_constrs = x_add unfolding prog is_all_constrs in
    let () = x_tinfo_hp (add_str "Unfolding result" 
        pr_hprel_list) is_all_constrs no_pos
    in
  
    let () = x_binfo_pp ">>>>> Step 3: Dangling Parameterizing <<<<<" no_pos in
    let is_all_constrs = x_add_1 dangling_parameterizing is_all_constrs in
    let () = x_binfo_hp (add_str "Parameterizing result" 
        pr_hprel_list) is_all_constrs no_pos
    in

    let () = x_binfo_pp ">>>>> Step 4: Inferring Segment Predicates <<<<<" no_pos in
    
    { is with CF.is_all_constrs = is_all_constrs }
  else is

let syn_pre_preds prog is = 
  let pr2 = Cprinter.string_of_infer_state_short in
  Debug.no_1 "Syn:syn_pre_preds" pr2 pr2
    (fun _ -> syn_pre_preds prog is) is
