# How to setup the Nexys4DDR nu+ Vivado project

A Vivado 2018.2 installation with Nexys 4 drivers should be used to execute the following steps. All the paths reported are relative to the project root.

 - Open a clean Vivado session
 - Select "Create Project"
 - Choose a project name (ex. `vivado_proj`) and location (ex. `boards/nexys4ddr`)
 - Select "RTL Project" as project type
 - Add the `src/` directory to the project sources
 - Add the `board/nexys4ddr/Nexys-4-DDR-Master.xdc` constraint file to the project
 - Select the "Nexys4 DDR" board from the part list
 - The project creation is now complete

 - In the Tcl console, run the following command: 
 `set_property file_type {Verilog Header} [get_files *_defines.sv]`
 - In the Sources pane, select the `nexys4ddr_top` as Top module
 - It is suggested to reduce the core area occupation by selecting out features in the `nuplus_user_defines.sv` header file; an example would be to reduce the `THREAD_NUMB` define to 4 and to comment out the `NUPLUS_SPM` and `NUPLUS_FPU` defines

 - From the IP Catalog, run the "Memory Interface Generator"
 - Use `mig_7series_0` as the component name
 - Select the "Verify Pin Changes and Update Design" option
 - Select the "AXI4 Interface" option
 - In the "Load Prj File" field, select the `boards/nexys4ddr/mig_7series_0/mig_a.prj` file
 - In the "Load UCF File" field, select the `boards/nexys4ddr/mig_7series_0/mig.ucf` file
 - Complete the IP core configuration
 - Skip the IP core output products generation
 - Open the `boards/nexys4ddr/vivado_proj.srcs/sources_1/ip/mig_7series_0/mig_a.prj` file
 - Find the XML element `InputClkFreq`, ensure that the element value is 200
 - Save and close the file
 - Generate the IP output products

 - From the IP Catalog, run the "Clocking Wizard"
 - Use `clk_wiz_0` as the component name
 - In the "Clocking Options" tab, ensure that the primary clock input signal `clk_in1` is set at 100 MHz
 - In the "Output Clocks" tab, enable the `clk_out1` output clock and set the frequency to 200 MHz
 - Ensure that the "Reset Type" is set to "Active High"
 - Complete the IP core configuration and generation
