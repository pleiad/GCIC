{ pkgs ? import <nixpkgs> {} }:
  
with pkgs;
mkShell {
  nativeBuildInputs = (with ocaml-ng.ocamlPackages_4_13; [
    ocaml stdio 
    menhir menhirLib sedlex_2
    dune_2 merlin ocamlformat findlib ocaml-lsp  utop
    alcotest qcheck qcheck-alcotest bisect_ppx
  ]) ++ [inotify-tools rlwrap];

  shellHook = ''
    alias dune-watch="dune build -w"
    alias dune-test="dune runtest"
    alias dune-coverage="dune runtest --instrument-with bisect_ppx --force; bisect-ppx-report html; bisect-ppx-report summary"
    alias dune-repl="rlwrap -m dune exec gcic"
    alias update-parser-errors="sh lib/parsing/update_error_msgs.sh"
  '';
}