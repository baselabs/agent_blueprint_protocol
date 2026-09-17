import Config

# Toolchain self-enforcement: the project refuses to build on an unsupported
# Erlang/OTP major before anything compiles. The supported set is every OTP
# major with official precompiled builds for the declared Elixir line,
# probed against builds.hex.pm and the official Docker images (decision
# record: docs/adr/supported-otp-set.md): Elixir 1.19 ships otp-26/27/28
# builds and 1.20 ships otp-27/28/29; OTP 26 is outside the supported
# matrix, leaving 27/28/29. The set moves in lockstep with mix.exs's
# :elixir range, .tool-versions, and the CI Elixir/OTP lanes — in one
# commit.
supported_otp = ["27", "28", "29"]
running_otp = to_string(:erlang.system_info(:otp_release))

unless running_otp in supported_otp do
  raise "Agent Blueprint Protocol supports Erlang/OTP #{Enum.join(supported_otp, "/")}; " <>
          "running #{running_otp} (Elixir #{System.version()}, code root #{:code.root_dir()})."
end
