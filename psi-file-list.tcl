set xvc_support_fw_files { \
  "rtl/Surf/StdRtlPkg.vhd" \
  "rtl/Surf/AxiStreamPkg.vhd" \
  "rtl/Axis2Jtag/AxisToJtagPkg.vhd" \
  "rtl/Axis2Jtag/JtagSerDesCore.vhd" \
  "rtl/Axis2Jtag/AxiStreamSelector.vhd" \
  "rtl/Axis2Jtag/AxisToJtagCore.vhd" \
  "rtl/Axis2Jtag/AxisToJtag.vhd" \
  "rtl/JtagTap/JtagTapFSM.vhd" \
  "rtl/JtagTap/JtagTapIR.vhd" \
  "rtl/Jtag2BSCAN/Jtag2BSCAN.vhd" \
  "rtl/BusIf/Tmem/Axis2TmemFifo.vhd" \
  "rtl/BusIf/Tmem/Tmem2BSCANWrapper.vhd" \
  "rtl/BusIf/Tmem/Tmem2BSCANConstraints.ucf" \
}

set xvc_support_location "[file dirname [info script]]"

proc xvc_support_add_srcs { pre } {
  global xvc_support_fw_files
  global xvc_support_location
  set xvcSupPath "[file dirname [info script]]"
  foreach f $xvc_support_fw_files {
    xfile add "$pre$xvc_support_location/$f"
  }
}
