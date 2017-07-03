#!/bin/bash

# Laurent LEQUIEVRE
# laurent.lequievre@uca.fr
# UMR 6602 - Institut Pascal

# NETWORK INFORMATIONS
# ====================
# sudo lshw -C network
# eth0 -> pci=0000:04:00.0, hw=68:05:ca:3e:3d:35, card=82574L Gigabit Network Connection, driver=e1000e
# eth1 -> pci=0000:06:00.0, hw=f0:4d:a2:32:39:d3, card=NetXtreme BCM5761 Gigabit Ethernet PCIe, driver=tg3
# eth2 -> pci=0000:22:00.0, hw=00:1b:21:b3:ae:27, card=82574L Gigabit Network Connection, driver=e1000e
# eth3 -> pci=0000:23:00.0, hw=68:05:ca:3e:3b:52, card=82574L Gigabit Network Connection, driver=e1000e
# eth4 -> pci=0000:24:00.0, hw=68:05:ca:3e:3d:36, card=82574L Gigabit Network Connection, driver=e1000e

# -> IP of right arm : 192.168.100.253  -> eth0 -> rteth0 -> pci=0000:04:00.0 -> hw=68:05:ca:3e:3d:35
# -> IP of left arm : 192.168.100.254 -> eth2 -> rteth1 -> pci=0000:22:00.0 -> hw=00:1b:21:b3:ae:27
# -> IP of the Master (the laptop) : 192.168.100.102

# Xenomai 2 + RTNET
prefix="/usr/local/rtnet"
prefix_bin="${prefix}/sbin"
modules_dir="${prefix}/modules"
rtifconfig="${prefix_bin}/rtifconfig"
rtroute="${prefix_bin}/rtroute"
module_ext=".ko"
rt_driver="rt_e1000e"
rt_driver_options=""

# PCI addresses of RT-NICs to claim (format: 0000:00:00.0)
#   If both Linux and RTnet drivers for the same hardware are loaded, this
#   list instructs the start script to rebind the given PCI devices, detaching
#   from their Linux driver, attaching it to the RT driver above. Example:
#   REBIND_RT_NICS="0000:00:19.0 0000:01:1d.1"
rebind_rt_nics=("0000:04:00.0" "0000:22:00.0")

ip_slaves=("192.168.100.253" "192.168.100.254")

hw_slaves=("68:05:ca:3e:3d:35" "00:1b:21:b3:ae:27")

master_ip_addr="192.168.100.101"
netmask="255.255.255.0"


# Use the following RTnet protocol drivers
rt_protocols=("udp" "tcp" "packet")

# Start realtime loopback device ("yes" or "no")
rt_loopback="no"

# Start capturing interface ("yes" or "no")
rt_cap="yes"

prepare_rtnet()
{
   echo "prepare_rtnet!"

   echo "Down eth0"
   ifconfig eth0 down

   echo "Down eth2"
   ifconfig eth2 down

   sleep 4

   echo "Remove module e1000e"
   rmmod e1000e

   echo "Remove module rt_e1000e"
   rmmod rt_e1000e

   echo "Remove module rtnet"
   rmmod rtnet

   echo "end prepare_rtnet()!"
}



up_rtnet()
{
   echo "up_rtnet!"

   i=0
   for hw_slave in ${hw_slaves[@]}; do
	echo "rtifconfig ${ip_slave} with ip=${ip_slaves[$i]} and rt=rteth$i !"
	$rtifconfig rteth$i up $master_ip_addr netmask $netmask hw ether ${hw_slave}
        i=$((i+1))
   done

   sleep 1

   i=0
   for ip_slave in ${ip_slaves[@]}; do
	echo "rtroute with ip=${ip_slave} and rt=rteth$i !"
        #$rtroute add ${ip_slave} ${hw_slaves[$i]} dev rteth$i
        $rtroute solicit ${ip_slave} dev rteth$i
        i=$((i+1))
   done

   echo "end up_rtnet()!"
}

init_rtnet() 
{
    echo "init_rtnet()!"

    insmod $modules_dir/rtnet$module_ext
    insmod $modules_dir/rtipv4$module_ext
    insmod $modules_dir/$rt_driver$module_ext $rt_driver_options

    for dev in ${rebind_rt_nics[@]}; do
        if [ -d /sys/bus/pci/devices/$dev/driver ]; then
          echo $dev > /sys/bus/pci/devices/$dev/driver/unbind
        fi
        echo $dev > /sys/bus/pci/drivers/$rt_driver/bind
    done

    for protocol in ${rt_protocols[@]}; do
        insmod $modules_dir/rt$protocol$module_ext
    done

    if [ $rt_loopback = "yes" ]; then
        insmod $modules_dir/rt_loopback$module_ext
    fi

    if [ $rt_cap = "yes" ]; then
        insmod $modules_dir/rtcap$module_ext
    fi

    if [ $rt_loopback = "yes" ]; then
        $rtifconfig rtlo up 127.0.0.1
    fi

    if [ $rt_cap = "yes" ]; then
        ifconfig rteth0 up
        ifconfig rteth0-mac up
	ifconfig rteth1 up
        ifconfig rteth1-mac up
        if [ $rt_loopback = "yes" ]; then
            ifconfig rtlo up
        fi
    fi

    insmod $modules_dir/rtcfg$module_ext
    insmod $modules_dir/rtmac$module_ext
    insmod $modules_dir/tdma$module_ext

    echo "end init_rtnet()!"
}



do_start()
{
  echo "do start!"
  prepare_rtnet
  init_rtnet
  up_rtnet
}

do_stop()
{
  echo "do_stop()!"

  ifconfig rteth0 down 2>/dev/null
  ifconfig rteth0-mac down 2>/dev/null
  ifconfig rtlo down 2>/dev/null

  i=0
  for ip_slave in ${ip_slaves[@]}; do
        echo "down rtifconfig ${ip_slave} !"
	$rtifconfig rteth$i down 2>/dev/null
  	i=$((i+1))
  done

   if [ $rt_loopback = "yes" ]; then
        $rtifconfig rtlo down 2>/dev/null
   fi

   for protocol in ${rt_protocols[@]}; do
        rmmod rt$protocol 2>/dev/null
   done

   rmmod tdma rtmac rtcfg rtcap rt_loopback $rt_driver rtipv4 rtnet 2>/dev/null

   for dev in $rebind_rt_nics; do
            echo 1 > /sys/bus/pci/devices/$dev/remove
   done
   
   if [ ! "$rebind_rt_nics" = "" ]; then
            sleep 1
            echo 1 > /sys/bus/pci/rescan
   fi

   #insmod e1000e$module_ext

   #i=0
   #hw=($hw_slaves)
   #ip=($ip_slaves)
   #for ip_slave in $ip_slaves; do
    #    ifconfig eth$i up $master_ip_addr netmask $netmask hw ether ${hw[$i]}
     #   route add -host ${ip[$i]} dev rteth$i
     #   i=$((i+2))
   #done
}


do_status()
{
  echo "rtifconfig result !"
  $rtifconfig

  echo "rtroute result !"
  $rtroute

  echo "ifconfig result !"
  ifconfig
}


# $0 correspond au nom du script lancé, $1 correspond au premier argument, $2 au deuxième argument ... 
case "$1" in
   start)
     echo "Start !"
     do_start
     ;;
   stop)
     echo "Stop !"
     do_stop
     ;;
   status)
     echo "Status !"
     do_status
     ;;
   restart|reload)
     echo "Restart/Reload !"
     do_stop
     do_start
     ;;
   *)
     echo "Usage: $0 {start|stop|restart|reload|status}"
     exit 1
esac
exit 0
