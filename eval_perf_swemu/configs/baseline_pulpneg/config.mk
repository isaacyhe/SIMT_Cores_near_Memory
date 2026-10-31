# baseline_pulpneg (real-RTL guard negative test)
# Uses hardware FP and M extension

MARCH = rv32imf
MABI = ilp32f

# No RTL overrides needed
VX_CONFIG_OVERRIDE = -DFPU_FPNEW -DDPI_DISABLE -DFPNEW_PULP_DIVSQRT 
