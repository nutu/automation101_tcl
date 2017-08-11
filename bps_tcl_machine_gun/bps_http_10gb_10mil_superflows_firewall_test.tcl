#The below will contain the IP and desired credentials that will be used when running the test
set bpsIP 10.200.119.242 ; #<IP-Of-Chassis>
set bpsPass nutu ; #<UserName-For the Chassis>
set bpsUser nutu ; #<PassWord - For the Chassis>

#The Next three commands selects the card number and ports where to run the test
set cardSlot 11 ; #<Integer: Position of the Card position like 1>
set port1 0 ; #<First Port Number Ex: 1>
set port2 1 ; #<2nd Port Number Ex 2>

#Connecting to the box from the shell.
set bps [bps::connect $bpsIP $bpsUser $bpsPass]

#Reserving the ports to run the test on this particular Chassis.
set chassisInstance [$bps getChassis]
$chassisInstance reservePort $cardSlot $port1
$chassisInstance reservePort $cardSlot $port2

#Creating the HelloWorld test based on an existing template AppSim.
set testInstance [$bps createTest -name "bps_http_10gb_10mil_superflows_firewall_test" -template AppSim]

# ---- MODIFY THE NETWORK EMULATED BY THE TEST ----
#Custumizing a new network "newNet" starting from the one set allready in the test
set templateNetworkName [$testInstance cget -neighborhood]
set newNet [$bps createNetwork -template $templateNetworkName]

#Get IP ranges asociated with test Interface 1 and reconfigure them. (in our template is only one)  
set if1_dict [$newNet getAll ip_static_hosts -container {Interface 1} ]
# if1_dict will be a dictionary of all ip ranges defined for Interface 1. 
# ex: {range1Name_key range1_obj range2Name_key range2_obj}
foreach { if1_iprange_key_name range_obj }  $if1_dict {
        puts "Configuring network ipv4 static host range \"$if1_iprange_key_name\" ..."
        incr x
        #configuring each range from Interface 1 with 10 Ips starting with 1.13.1.1 mask 16 and the firewall port IP as gateway
        #to see all the parameters do : $range_obj  configure
        set err [ $range_obj  configure -count 10 -ip_address 40.1.${x}.1 -netmask 16  -gateway_ip_address 40.1.0.254 -netmask 16]
        if {$err != ""} {puts "Could not configure : $if1_iprange_key_name because $err"}
}

#Get IP ranges asociated with test Interface 2 and reconfigure them. (in our template is only one) 
set if2_dict [$newNet getAll ip_static_hosts -container {Interface 2} ]
foreach { if2_iprange_key_name range_obj }  $if2_dict  {
        puts "Configuring network ipv4 static host range \"$if2_iprange_key_name\" ..."
        incr y
        set err [ $range_obj  configure -count 10 -ip_address 40.2.${x}.1 -gateway_ip_address 40.2.0.254 -netmask 16 ]
        if {$err != ""} {puts "Could not configure : $if2_iprange_key_name because $err"}
}
#save the new created
$newNet save -name "nn_firewall" -force
#configure the new created network to be used in the test
$testInstance configure -network "nn_firewall"

# ------Checking the appsim traffic componenet settings ----
#Navigating to the object for component named appsim1
set component_dict [$testInstance getComponents] 
set appsim_component_obj [dict get $component_dict appsim1]
#Modify appsim component parameters : throughput at 10 Gbps, 1Million super flows per second and concurrency as 10Million
$appsim_component_obj configure -rateDist.min          10000
$appsim_component_obj configure -sessions.maxPerSecond 1000000
$appsim_component_obj configure -sessions.max          10000000

$appsim_component_obj configure -app.streamsPerSuperflow 1

#Modify test load profile durations : a ramp up of 30 seconds , steady of 75 seconds ramp down of 15 load profile
$appsim_component_obj configure -rampDist.up          30
$appsim_component_obj configure -rampDist.steady      75
$appsim_component_obj configure -rampDist.down        15

#Modify the traffic aplications to HTTP GET /200k (Designed for bandwith)
$appsim_component_obj configure -profile {BreakingPoint Bandwidth_HTTP}

#Printing some of the configuration : to see all the parameters do : $appsim_component_obj configure

set trafic_profile               [$appsim_component_obj cget -profile]
set tput_minimum_data_rate       [$appsim_component_obj cget -rateDist.min]
set tput_target_unit             [$appsim_component_obj cget -rateDist.unit]
set max_simultaneous_super_flows [$appsim_component_obj cget -sessions.max]
set max_super_flows_per_sec      [$appsim_component_obj cget -sessions.maxPerSecond]
set app_streams_per_super_flow   [$appsim_component_obj cget -app.streamsPerSuperflow]

set loadprofile_ramp_down   [$appsim_component_obj cget -rampDist.down]
set loadprofile_ramp_steady [$appsim_component_obj cget -rampDist.steady]
set loadprofile_ramp_up     [$appsim_component_obj cget -rampDist.up]

puts "********* $trafic_profile  CONFIGURATION SUMMARY ********"
puts "Testing the firewall with traffic profile : \"$trafic_profile\" "
puts "Targeting Data Rate : $tput_minimum_data_rate $tput_target_unit bidirectional per interface traffic"
puts "Targeting Superflow : $max_simultaneous_super_flows Simultaneous\
  at a max $max_super_flows_per_sec superflow per sec with $app_streams_per_super_flow streams per each flow"
puts "Load Profile  ramp up: $loadprofile_ramp_up sustain: $loadprofile_ramp_steady, ramp down: $loadprofile_ramp_down"

puts "*********"
#saving the test with a new name
$testInstance save -name bps_http_10gb_10mil_superflows_firewall_test -force

#Running the created test. Setting the status variable to the output.
puts "Starting [$testInstance cget -name] test"
set status [$testInstance run -progress "bps::textprogress stdout"]

#RESULTS#
#Navigating to the object for component named appsim1
set component_dict [$testInstance getComponents] 
set appsim_component_obj [dict get $component_dict appsim1]
set agregated_components_obj [dict get $component_dict aggstats]

set trafic_profile [$appsim_component_obj cget -profile]
#obtaining the result object for appsim and overall aggregated stats
set appsim_result   [$appsim_component_obj result]
set aggstats_result [$agregated_components_obj result]

#list apps in the mix
puts "*********"
puts "Executed $trafic_profile traffic profile contains the following protocols: "
set apps [$appsim_result protocols]
foreach app [lrange $apps 1 end] { 
    incr m
    puts "$m# $app"
}
puts "********* RESULTS ********"
#print a result summary
puts "Traffic combination $trafic_profile TX TPUT:  [$appsim_result get appTxFrameDataRate] mbps"
puts "Traffic combination $trafic_profile RX TPUT:  [$appsim_result get appRxFrameDataRate] mbps"
puts "Overall Super Flow Rate:  [$aggstats_result get superFlowRate]/s"
puts "Overall Concurrent Super Flows:  [$aggstats_result get superFlowsConcurrent]"
puts "Unsuccessfull application atempts:  [$appsim_result get appUnsuccessful]"

#get all summary stats names availlable with names containing bad word below and printing the value if not 0
set bad_words_to_match ".*error|invalid|unknown|aborted|router|exception|unconfigured|retries|timeout|reset.*"

puts "Traffic errors if any: "
foreach statName [$aggstats_result values] { 
    if {[regexp -nocase $bad_words_to_match $statName] && [ $aggstats_result get $statName ] !="0"} {
        puts "*!Overall $statName:  [ $aggstats_result get $statName ]"
    }
}
foreach statName [$appsim_result values] { 
    if {[regexp -nocase $bad_words_to_match $statName] && [ $appsim_result get $statName ] !="0"} {
        puts "*!Component's $statName:  [ $appsim_result get $statName ]"
    }
}

#If the tests criteria are met (in this case if more than 95% of the session succeeded), test will report Pass
puts "Test finished with status $status"
puts "********* $trafic_profile END EXECUTION AND ANALYSIS ********"
