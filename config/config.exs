import Config

supported_otp = ["27", "28", "29"]
running_otp = to_string(:erlang.system_info(:otp_release))

unless running_otp in supported_otp do
  raise "Agent Blueprint Protocol supports Erlang/OTP #{Enum.join(supported_otp, "/")}; " <>
          "running #{running_otp} (Elixir #{System.version()}, code root #{:code.root_dir()})."
end
