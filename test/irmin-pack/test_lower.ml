(*
 * Copyright (c) 2023 Tarides <contact@tarides.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open! Import
open Common

let src = Logs.Src.create "tests.lower" ~doc:"Test lower"

module Log = (val Logs.src_log src : Logs.LOG)
module Io = Irmin_pack_unix.Io.Unix

let ( let$ ) res f = f @@ Result.get_ok res

let rec unlink path =
  match Irmin_pack_unix.Io.Unix.classify_path path with
  | `No_such_file_or_directory -> ()
  | `Directory ->
      Sys.readdir path
      |> Array.map (fun p -> Filename.concat path p)
      |> Array.iter unlink;
      Unix.rmdir path
  | _ -> Unix.unlink path

module Direct_tc = struct
  module Control = Irmin_pack_unix.Control_file.Volume (Io)
  module Errs = Irmin_pack_unix.Io_errors.Make (Io)
  module Lower = Irmin_pack_unix.Lower.Make (Io) (Errs)

  let create_lower_root =
    let counter = ref 0 in
    fun () ->
      let lower_root = "test_lower_" ^ string_of_int !counter in
      incr counter;
      let lower_path = Filename.concat "_build" lower_root in
      unlink lower_path;
      let$ _ = Irmin_pack_unix.Io.Unix.mkdir lower_path in
      lower_path

  let create_control volume_path payload =
    let path = Irmin_pack.Layout.V5.Volume.control ~root:volume_path in
    Control.create_rw ~path ~overwrite:true payload

  let test_empty () =
    let lower_root = create_lower_root () in
    let$ lower = Lower.v ~readonly:false ~volume_num:0 lower_root in
    Alcotest.(check int) "0 volumes" 0 (Lower.volume_num lower);
    let _ = Lower.close lower in
    Lwt.return_unit

  let test_volume_num () =
    let lower_root = create_lower_root () in
    let result = Lower.v ~readonly:false ~volume_num:1 lower_root in
    let () =
      match result with
      | Error (`Volume_missing _) -> ()
      | _ -> Alcotest.fail "volume_num too high should return an error"
    in
    Lwt.return_unit

  let test_add_volume () =
    let lower_root = create_lower_root () in
    let$ lower = Lower.v ~readonly:false ~volume_num:0 lower_root in
    let$ _ = Lower.add_volume lower in
    Alcotest.(check int) "1 volume" 1 (Lower.volume_num lower);
    let$ _ = Lower.reload ~volume_num:1 lower in
    Alcotest.(check int) "1 volume after reload" 1 (Lower.volume_num lower);
    let _ = Lower.close lower in
    Lwt.return_unit

  let test_add_volume_ro () =
    let lower_root = create_lower_root () in
    let$ lower = Lower.v ~readonly:true ~volume_num:0 lower_root in
    let result = Lower.add_volume lower in
    let () =
      match result with
      | Error `Ro_not_allowed -> ()
      | _ -> Alcotest.fail "cannot add volume to ro lower"
    in
    let _ = Lower.close lower in
    Lwt.return_unit

  let test_add_multiple_empty () =
    let lower_root = create_lower_root () in
    let$ lower = Lower.v ~readonly:false ~volume_num:0 lower_root in
    let$ _ = Lower.add_volume lower in
    let result = Lower.add_volume lower |> Result.get_error in
    let () =
      match result with
      | `Multiple_empty_volumes -> ()
      | _ -> Alcotest.fail "cannot add multiple empty volumes"
    in
    let _ = Lower.close lower in
    Lwt.return_unit

  let test_find_volume () =
    let lower_root = create_lower_root () in
    let$ lower = Lower.v ~readonly:false ~volume_num:0 lower_root in
    let$ volume = Lower.add_volume lower in
    let payload =
      Irmin_pack_unix.Control_file.Payload.Volume.Latest.
        {
          start_offset = Int63.zero;
          end_offset = Int63.of_int 42;
          mapping_end_poff = Int63.zero;
          data_end_poff = Int63.zero;
          checksum = Int63.zero;
        }
    in
    let _ = create_control (Lower.Volume.path volume) payload in
    let volume = Lower.find_volume ~offset:(Int63.of_int 21) lower in
    Alcotest.(check bool)
      "volume not found before reload" false (Option.is_some volume);
    let$ _ = Lower.reload ~volume_num:1 lower in
    let volume = Lower.find_volume ~offset:(Int63.of_int 21) lower in
    Alcotest.(check bool) "found volume" true (Option.is_some volume);
    let _ = Lower.close lower in
    Lwt.return_unit
end

module Store_tc = struct
  module Store = struct
    module Maker = Irmin_pack_unix.Maker (Conf)
    include Maker.Make (Schema)
  end

  let test_dir = "_build"

  let mkdir_if_needed path =
    match Io.mkdir path with
    | Error (`File_exists _) | Ok () -> Ok ()
    | _ as r -> r

  let fresh_roots =
    let c = ref 0 in
    fun () ->
      incr c;
      let name =
        Filename.concat test_dir ("test_lower_store_" ^ string_of_int !c)
      in
      let$ _ = mkdir_if_needed name in
      let lower = Filename.concat name "lower" in
      let$ _ = mkdir_if_needed lower in
      (name, lower)

  let init ?(readonly = false) ?(fresh = true) ?(unlink_lower = true) ?config ()
      =
    (* [unlink_lower] defaults to true to make dir clean for multiple test runs. *)
    let config =
      match config with
      | None ->
          let root, lower_root = fresh_roots () in
          if unlink_lower then unlink lower_root;
          Irmin_pack.(
            config ~readonly ~indexing_strategy:Indexing_strategy.minimal ~fresh
              ~lower_root:(Some lower_root) root)
      | Some c -> c
    in
    Store.Repo.v config

  let test_create () =
    let* repo = init () in
    (* A newly created store with a lower should have an empty volume. *)
    let volume_num =
      Store.Internal.(
        file_manager repo
        |> File_manager.lower
        |> Option.map File_manager.Lower.volume_num
        |> Option.value ~default:0)
    in
    Alcotest.(check int) "volume_num is 1" 1 volume_num;
    Store.Repo.close repo

  let test_add_volume_during_gc () =
    let* repo = init () in
    let* main = Store.main repo in
    let* () =
      Store.set_exn
        ~info:(fun () -> Store.Info.v ~author:"tester" Int64.zero)
        main [ "a" ] "a"
    in
    let* c = Store.Head.get main in
    let* _ = Store.Gc.start_exn repo (Store.Commit.key c) in
    let* () =
      Alcotest.check_raises_lwt "add volume during gc"
        (Irmin_pack_unix.Errors.Pack_error `Add_volume_forbidden_during_gc)
        (fun () -> Store.add_volume repo |> Lwt.return)
    in
    Store.Repo.close repo

  let test_add_volume_reopen () =
    (* TODO: test adding a volume and reopning store to
       ensure conrol file is updated correclty. *)
    Lwt.return_unit
end

module Store = struct
  include Store_tc

  let tests =
    Alcotest_lwt.
      [
        quick_tc "create store" test_create;
        quick_tc "add volume during gc" test_add_volume_during_gc;
        quick_tc "control file updated after add" test_add_volume_reopen;
      ]
end

module Direct = struct
  include Direct_tc

  let tests =
    Alcotest_lwt.
      [
        quick_tc "empty lower" test_empty;
        quick_tc "volume_num too high" test_volume_num;
        quick_tc "add volume" test_add_volume;
        quick_tc "add volume ro" test_add_volume_ro;
        quick_tc "add multiple empty" test_add_multiple_empty;
        quick_tc "find volume" test_find_volume;
      ]
end
