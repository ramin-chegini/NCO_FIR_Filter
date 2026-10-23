# Run from any directory: vivado -mode batch -source scripts/create_project.tcl
# Optional Tcl arguments: --debug and --synth.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set debug_enabled [expr {[lsearch -exact $argv --debug] >= 0}]
set run_synthesis [expr {[lsearch -exact $argv --synth] >= 0}]
foreach arg $argv {
    if {$arg ni {--debug --synth}} { error "Unknown argument: $arg" }
}
set variant [expr {$debug_enabled ? "debug" : "release"}]
set build_root [file normalize [file join $repo_root build]]
set project_dir [file normalize [file join $build_root $variant]]
# Validate the absolute target before removing this script's generated variant.
if {[file dirname $project_dir] ne $build_root || $variant ni {release debug}} {
    error "Refusing to replace an output outside the build directory: $project_dir"
}
if {[file exists $project_dir]} { file delete -force $project_dir }
create_project NCO_FIR_Filter $project_dir -part xcku060-ffva1156-2-i
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property enable_core_container false [current_project]
add_files -norecurse [list \
    [file join $repo_root HDL programmble_Dec.vhd] \
    [file join $repo_root HDL TopM.vhd]]
set ip_names {dds_NCO mult_16_bit fir_coef_load}
if {$debug_enabled} { lappend ip_names ila_0 ila_2 ila_3 }
# Preserve the FIR XCI's ../../Coe reference while the copied IP is first read.
file mkdir [file join $project_dir Coe]
file copy -force [file join $repo_root Coe fir_nco_40Mbw.coe] [file join $project_dir Coe]
foreach ip_name $ip_names {
    # Copy only the customization. import_ip also tries to copy missing outputs
    # recorded inside an archived XCI, which causes misleading critical warnings.
    set ip_dir [file join $project_dir ip $ip_name]
    file mkdir $ip_dir
    file copy -force [file join $repo_root IP $ip_name ${ip_name}.xci] $ip_dir
    read_ip [file join $ip_dir ${ip_name}.xci]
    # Match standalone IP synthesis clocks to the top-level 128 MHz clock.
    # Clock-interface customization names differ between the vendor cores.
    set ip_object [get_ips $ip_name]
    foreach property_name [list_property $ip_object] {
        if {[regexp -nocase {^CONFIG\.((aclk|clk)(_intf)?|signal_clock)\.FREQ_HZ$} $property_name]} {
            set_property $property_name 128000000 $ip_object
        }
    }
}
set_property top TopM [get_filesets sources_1]
set debug_literal [expr {$debug_enabled ? "true" : "false"}]
set_property generic ENABLE_DEBUG=$debug_literal [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $repo_root Constraints timing.xdc]
update_compile_order -fileset sources_1
reset_target all [get_ips]
generate_target all [get_ips]
if {$run_synthesis} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "Synthesis failed; inspect the run log in $project_dir."
    }
    open_run synth_1
    set latches [get_cells -quiet -hier -filter {REF_NAME =~ LD*}]
    if {[llength $latches]} { error "Unexpected latches: $latches" }
    # Vivado inserts dbg_hub for ILA designs and resolves it at implementation.
    set black_boxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1 && NAME != dbg_hub}]
    if {[llength $black_boxes]} { error "Unresolved IP black boxes: $black_boxes" }
    report_utilization -file [file join $project_dir utilization.rpt]
    report_timing_summary -file [file join $project_dir timing_summary.rpt]
}
puts "Project ready: [file join $project_dir NCO_FIR_Filter.xpr]"
