node = System.find_executable("node") || raise "node missing"

{output, status} =
  System.cmd(node, ["scripts/check_release_promotion.mjs" | System.argv()],
    stderr_to_stdout: true
  )

IO.write(output)
if status != 0, do: raise("release promotion failed")
