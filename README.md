## Irmin

Irmin is a library for persistent stores with built-in snapshot,
branching and reverting mechanisms. It is designed to use a large
variety of backends. Irmin is written in pure OCaml and does not
depend on external C stubs; it aims is to run everywhere, from Linux
to Xen unikernels.

[![Build Status](https://travis-ci.org/mirage/irmin.png?branch=master)](https://travis-ci.org/mirage/irmin)

### Install

Irmin is packaged with [opam](https://opam.ocaml.org):

```
opam install irmin
```

### Usage

Irmin comes with a command-line tool called `irmin`. See `irmin
 --help` for further reading. Use either `irmin <command> --help` or
 `irmin help <command>` for more information on a specific command.

To get the full capabilites of Irmin, use the API:

```ocaml
$ ledit ocaml
# #require "irmin.unix";;
# open Lwt;;
# let store = Irmin.basic (module Irmin_git.FS) (module Irmin.Contents.String);;
# let config = Irmin_git.config ~root:"/tmp/irmin/test" ~bare:true ();;
# let prog =
    Irmin.create store config >>= fun t ->
    Irmin.update (t "Updating foo/bar")  ["foo"; "bar"] "hi!" >>= fun () ->
    Irmin.read_exn (t "Reading foo/bar") ["foo"; "bar"] >>= fun x ->
    Printf.printf "Read: %s\n%!" x;
    return_unit;;
# let () = Lwt_main.run prog;;
```

### Tutorial

A tutorial is available on the [wiki](https://github.com/mirage/irmin/wiki/Getting-Started).

### Issues

To report any issues please use the [bugtracker on Github](https://github.com/mirage/irmin/issues).
