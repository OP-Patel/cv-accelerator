# Run from inside the scripts/ directory:
#   vivado -mode batch -source build_bitstream.tcl
# Assumes create_project.tcl has already been run once.

open_project ../vivado_project/arty_conv.xpr

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream generated: [glob ../vivado_project/arty_conv.runs/impl_1/*.bit]"

open_run impl_1
report_timing_summary -file ../docs/timing_summary_milestone1.rpt
report_utilization -file ../docs/utilization_milestone1.rpt