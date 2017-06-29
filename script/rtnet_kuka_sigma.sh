#!/bin/sh

# Laurent LEQUIEVRE
# laurent.lequievre@univ-bpclermont.fr
# UMR 6602 - Institut Pascal

# NETWORK INFORMATIONS
# ====================
# sudo lshw -C network
# eth0 -> pci=0000:04:00.0, hw=68:05:ca:3e:3d:35, card=82574L Gigabit Network Connection, driver=e1000e
# eth1 -> pci=0000:06:00.0, hw=f0:4d:a2:32:39:d3, card=NetXtreme BCM5761 Gigabit Ethernet PCIe, driver=tg3
# eth2 -> pci=0000:22:00.0, hw=00:1b:21:b3:ae:27, card=82574L Gigabit Network Connection, driver=e1000e
# eth3 -> pci=0000:23:00.0, hw=68:05:ca:3e:3b:52, card=82574L Gigabit Network Connection, driver=e1000e
# eth4 -> pci=0000:24:00.0, hw=68:05:ca:3e:3d:36, card=82574L Gigabit Network Connection, driver=e1000e

xenomai_prefix="/usr/xenomai_2_6_5"
xenomai_prefix_bin="/usr/xenomai_2_6_5/sbin"

rtnet_prefix="/usr/local/rtnet"
rtnet_prefix_bin="$rtnet_prefix/sbin"

# Associate rtethX to ethX
# rteth0 -> kuka left
# rteth1 -> kuka right
rtethX_associate_kuka_left="rteth0"
rtethX_associate_kuka_right="rteth1"

# eth2 -> kuka left
# eth0 -> kuka right
# eth3 -> switch
ethX_associate_kuka_left="eth2"
ethX_associate_kuka_right="eth0"
ethX_associate_switch="eth3"

# PCI address of each ethX associated
pci_address_associate_kuka_left="0000:22:00.0"
pci_address_associate_kuka_right="0000:04:00.0"

# Define IP address for RT eth0 and eth1
ip_address_associate_kuka_left="192.168.100.102"
ip_address_associate_kuka_right="192.168.100.120"
ip_address_master_rt_net="192.168.100.101"
ip_address_associate_switch="192.168.100.123"
ip_address_associate_sub_net_switch="192.168.100.0/24"

# Define Netmask for RT eth0 and eth1
netmask_associate_kuka_left="255.255.255.0"
netmask_associate_kuka_right="255.255.255.0"
netmask_associate_switch="255.255.255.0"

# Define hw of each ethX associated
hw_ethX_associate_kuka_left="00:1b:21:b3:ae:27"
hw_ethX_associate_kuka_right="68:05:ca:3e:3d:35"
hw_ethX_associate_switch="68:05:ca:3e:3b:52"

# Define IP address of kuka arms
ip_address_kuka_right="192.168.100.253"
ip_address_kuka_left="192.168.100.254"

# Define IP address for local loopback
ip_address_loopback="127.0.0.1"

# Define the name of the RT driver
rt_driver="rt_e1000e"


do_start()
{
	echo "Start net script (RT and non RT) of kuka left and right arms and also switch !"
	
	echo "ifconfig down (non RT) ethX associate to kuka left and right !"
	sudo ifconfig $ethX_associate_kuka_left down
	sudo ifconfig $ethX_associate_kuka_right down
	
	echo "ifconfig down (non RT) ethX associated to switch !"
	sudo ifconfig $ethX_associate_switch down
	
	echo "Load (RT) linux modules !"
	sudo modprobe rt_e1000e
    	sudo modprobe rtnet
    	sudo modprobe rtipv4
    	sudo modprobe rtcfg
    	sudo modprobe rtudp
    	sudo modprobe rtpacket
    	sudo modprobe rt_loopback
	
	
	
	echo "**** Start (RT) config (rteth0) of kuka left !"
	echo $pci_address_associate_kuka_left > /sys/bus/pci/devices/$pci_address_associate_kuka_left/driver/unbind
	echo $pci_address_associate_kuka_left > /sys/bus/pci/drivers/$rt_driver/bind

	echo "rtifconfig up rteth0 for kuka left !"
	sudo $rtnet_prefix_bin/rtifconfig $rtethX_associate_kuka_left up $ip_address_master_rt_net netmask $netmask_associate_kuka_left hw ether $hw_ethX_associate_kuka_left
	
	echo "**** Start (RT) config (rteth1) of kuka right !"
	echo $pci_address_associate_kuka_right > /sys/bus/pci/devices/$pci_address_associate_kuka_right/driver/unbind
	echo $pci_address_associate_kuka_right > /sys/bus/pci/drivers/$rt_driver/bind

	echo "rtifconfig up rteth1 for kuka right !"
	sudo $rtnet_prefix_bin/rtifconfig $rtethX_associate_kuka_right up $ip_address_master_rt_net netmask $netmask_associate_kuka_right hw ether $hw_ethX_associate_kuka_right
	
	echo "Start rtlo !"
	sudo $rtnet_prefix_bin/rtifconfig rtlo up $ip_address_loopback

	echo "Add (RT) route to kuka left arm"
	sleep 5
	sudo $rtnet_prefix_bin/rtroute solicit $ip_address_kuka_left dev $rtethX_associate_kuka_left

	echo "Add (RT) route to kuka right arm"
	sleep 5
	sudo $rtnet_prefix_bin/rtroute solicit $ip_address_kuka_right dev $rtethX_associate_kuka_right
	
	echo "Start ethX (non RT) associate to switch !"
	sudo ifconfig $ethX_associate_switch up $ip_address_associate_switch netmask $netmask_associate_switch hw ether $hw_ethX_associate_switch $ip_address_associate_switch
      
}

do_stop()
{
	echo "Stop net script (RT) !"
	
	echo "Stop ethX (RT) associate to kuka left !"
	sudo $rtnet_prefix_bin/rtifconfig $rtethX_associate_kuka_left down

	sleep 1
	echo '1' > /sys/bus/pci/devices/$pci_address_associate_kuka_left/remove

    	sleep 1
	echo '1' > /sys/bus/pci/rescan
	# These tests doesn' t work !
	#echo '1' > sudo tee /sys/bus/pci/rescan
    	#sudo sh -c "echo '1' > /sys/bus/pci/rescan"
	
	sleep 1    
    	echo "Stop ethX (RT) associate to kuka right !"
    	sudo $rtnet_prefix_bin/rtifconfig $rtethX_associate_kuka_right down
    	
	sleep 1
	echo '1' > /sys/bus/pci/devices/$pci_address_associate_kuka_right/remove

    	sleep 1
	echo '1' > /sys/bus/pci/rescan
    
    	echo "Stop (RT) lo !"
	sudo $rtnet_prefix_bin/rtifconfig rtlo down

    	echo "Remove RT modules !"
    	sudo rmmod rtcfg rt_loopback rt_e1000e rtpacket rtudp rtipv4 rtnet
    
    	echo "ifconfig up ethX associate to kuka arms left and right !"
    	sudo ifconfig $ethX_associate_kuka_left up $ip_address_associate_kuka_left netmask $netmask_associate_kuka_left hw ether $hw_ethX_associate_kuka_left
    	sudo ifconfig $ethX_associate_kuka_right up $ip_address_associate_kuka_right netmask $netmask_associate_kuka_right hw ether $hw_ethX_associate_kuka_right

    	echo "Add route (non RT) to kuka left arm !"
    	sleep 5
    	sudo route add -host $ip_address_kuka_left dev $ethX_associate_kuka_left
	
    	echo "Add route (non RT) to kuka right arm !"
    	sleep 5
    	sudo route add -host $ip_address_kuka_right dev $ethX_associate_kuka_right
}


if [ -c /dev/rtnet ] 
 then
   echo "/dev/rtnet management device node exists !"
 else
   # Create the RTnet management device node
   echo "Create RTnet management device node"
   mknod /dev/rtnet c 10 240   
fi


case "$1" in
   start)
      do_start
      ;;
   stop)
      do_stop
      ;;
   *)
      echo "--> Usage: $0 {start|stop}"
      exit 1
esac

exit 0
