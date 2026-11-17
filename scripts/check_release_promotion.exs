node = System.find_executable("node") || raise "node missing"

{_, status} =
  System.cmd(node, ["scripts/check_release_promotion.mjs" | System.argv()],
    into: IO.stream(),
    stderr_to_stdout: true
  )

if status != 0, do: raise("release promotion failed")
