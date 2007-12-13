#! /usr/bin/perl -w

# NAME
# winkeydaemon - morse daemon for the winkey hardware keyer module
#
# SYNOPSIS
# winkeydaemon [options] ...
# 
# OPTIONS
# -n  Run in debug mode
# -p  UDP port (default is 6789)
# -s  Speed (default is 24 wpm)
# -d  Serial device (default is /dev/ttyS0)
#
# DESCRIPTION
#
# winkeydaemon.pl is a driver for the winkey2 keyer. It provides an interface 
# which is compatible to the cwdaemon, which means it can be used instead of 
# the cwdaemon. 
# The winkeydaemon listens to a udp socket # and outputs commands to the k1el 
# keyer on a serial port.
#

# The k1el_daemon implements the following cwdaemon-compatible commands:
# <ESC>"0"                 Reset to default values
# <ESC>"2"<"speed value">  Set keying speed (5 ... 60 wpm)
# <ESC>"4"                 Abort message
# <ESC>"5"                 Stop (Exit) the daemon
# <ESC>"7"<"weight value"> Set weighting (-50 ... 50)
# <ESC>"c"<"x">            Tune x seconds long (limit = 10 seconds)
# <ESC>"d"<"delay">        PTT on delay 0..50 (0 .. 50ms)
# Any message              Send morse code message  (max 1 packet!)
# qrz de pa0rct ++test--   In- and decrease speed on the fly in 4 wpm steps
#
# COPYING
#
# This program is published under the GPL license.
#   Copyright (C) 2007, 2008
#       Rein Couperus PA0R (rein at couperus.com)
#
# *    winkeydaemon.pl is free software; you can redistribute it and/or modify
# *    it under the terms of the GNU General Public License as published by
# *    the Free Software Foundation; either version 2 of the License, or
# *    (at your option) any later version.
# *
# *    winkeydaemon.pl is distributed in the hope that it will be useful,
# *    but WITHOUT ANY WARRANTY; without even the implied warranty of
# *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# *    GNU General Public License for more details.
# *
# *    You should have received a copy of the GNU General Public License
# *    along with this program; if not, write to the Free Software
# *    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

## Version 1.0, 13/12/2007

use Device::SerialPort qw( :PARAM :STAT 0.07 );
use IO::Socket;
use Getopt::Std;

my $myserver;
my $cnt = 0;
my $string = "";
my $debug = 0;
my $speed = 30;
my $serial = "/dev/ttyS0";
my $server_port = 6789;
my $mutexdir = "$ENV{HOME}/.winkey";

getopts("np:s:d:");

if ($opt_p) {
	$server_port = $opt_p;
} 

if ($opt_s) {
	$speed = $opt_s;
}
if ($opt_d) {
	$serial = $opt_d;
}

if (-d "$ENV{HOME}/.winkey") {
	# ok, no action required
} else {
	my $dir = "$ENV{HOME}/.winkey";
	`mkdir "$dir"`;
	if ($debug) {print "Arranging mutex directory\n";}
}

########## Initialize the serial port

 my $port=Device::SerialPort->new($serial);
 
  $port->baudrate(1200);
  $port->parity("none");
  $port->databits(8);
  $port->stopbits(1); 
 
  $port->dtr_active(1); 
  $port->rts_active(0);

sleep 1;

my $timeout = 0;
 
 $port->read_char_time(0); 
 $port->read_const_time(0); 	
 
 ########## Initialize the udp port
  
 $server = IO::Socket::INET->new(LocalPort => $server_port, Proto => "udp")
 	or die "Couldn't setup udp server on port $server_port : $@\n";
 	
########### Initialize keyer
 
$reset = sprintf("%c%c", 0x00, 0x01);	## reset
  $count = $port->write($reset);
  
  select undef,undef,undef, 0.3;


 $setmode = sprintf ("%c%c", 0x0E, 0x17); ## set mode
  $count = $port->write($setmode);
 
   select undef,undef,undef, 0.3;
    
 my $setpins = sprintf ("%c%c", 0x09, 0x05);	## set pinout
				$count = $port->write($setpins);

    select undef,undef,undef, 0.2;


	 $senddelay = sprintf ("%c%c%c", 0x04, 0x01, 0x00);
	 $count = $port->write($senddelay);

sleep 1;

 $keyeropen = sprintf ("%c%c", 0x00, 2);		## open keyer interface
 $count = $port->write($keyeropen);
# sleep 1;
 
	$setspeed = sprintf ("%c%c", 0x1C, $speed);  ## set the default speed
	$count = $port->write($setspeed);


 
if ($opt_n) {
	$opt_n = 0;
	$debug = 1;
	Do_operations();	## do not fork, debug
} else {
	if (fork) {			## run as daemon
		exit;
	} else {
		for my $handle (*STDIN,*STDOUT, *STDERR) { # silent...
			open $handle, "+<", "/dev/null" 
			or die "Cannot reopen $handle to /dev/null: $!";
		}
		Do_operations();
	}

}

exit;


 ########## Start operations ########
 sub Do_operations {
 ####################################
 
 my $busy = 0;
 my $echo = "";
 
   $count = $port->write("QRV");
 
while (1) {
  
	if ($cnt > 31) { 
	eval {
	    local $SIG{ALRM} = sub { die "alarm time out" };
	    alarm 1;

			$myserver = $server->recv($datagram, 32);
			
	    alarm 0;
		    1;  # return value from eval on normalcy
	};
		$cnt = 0;
	} else {
		$cnt++;
	}
	
	if ($datagram) {
		my @chars = split '', $datagram;

		if (ord($chars[0]) == 27) {
		
		 	if ($chars[1] eq "2") {		## set speed
		 		$speed = $chars[2] . $chars[3];
				$setspeed = sprintf ("%c%c", 0x02, $speed);
				$count = $port->write($setspeed);
				if ($debug) {print "Speed=$speed\n";}
		 	} elsif ($chars[1] eq "5") {  ## exit daemon
		 		last;
		 	} elsif ($chars[1] eq "7") {  ## set weight
		 		if ($chars[2] eq "-") {
		 			if (ord($chars[4]) == 0) {
		 				$wgt = $chars[2] . $chars[3] ;
		 			} else {
		 				$wgt = $chars[2] . $chars[3] . $chars[4];
		 			}
		 		} else {
		 			if (ord($chars[3]) == 0) {
		 				$wgt = $chars[2];
		 			} else {
		 				$wgt = $chars[2] . $chars[3];
		 			}
		 			
		 		}
		 		$wgt += 50;
		 		if ($wgt < 10) { $wgt = 10;}
		 		if ($wgt > 90) { $wgt = 90;}
		 		
		 		if ($debug) {print "weight=$wgt\n";}
				my $setweight = sprintf ("%c%c", 0x03, $wgt);
				$count = $port->write($setweight);
		 	} elsif ($chars[1] eq "d") {  ## set PTT lead in (00...50)
				if (ord($chars[3]) == 0) {
					$delay = 0;
					$delaybyte = 0x02;
				} else {
					$delay = $chars[2] . $chars[3];
					$delaybyte = int ($delay / 10);			
				}
				
				if ($debug) { print "PTT lead in = $delay\n";}
				
				if ($delaybyte > 5) { $delaybyte = 5; }
				
				$senddelay = sprintf ("%c%c%c", 0x04, $delaybyte, 0x00);				
				$count = $port->write($senddelay);
				
		 	} elsif ($chars[1] eq "c") {  ## TUNE
		 		if ($tune_on) { 
		 			$tune_on = 0;
		 			if ($debug) { print "Tune off\n";}
		 		} else {
		 			$tune_on = 1;
		 			if ($debug) { print "Tune on\n";}
		 		}
		 		my $tuning = sprintf("%c%c", 0x0B, $tune_on);
				$count = $port->write($tuning);
		 		
		 	} else {
		 		$stopkeying = sprintf("%c", 0x0A);
				$count = $port->write($stopkeying);	 		
		 	}
		 	$datagram = "";

		} else {
			foreach $c (@chars) {
				$cr = ord($c);
				if (($cr > 47 && $cr < 58) || ($cr > 64 && $cr < 91) || $cr == 32) { # only 0-9A-Z
					$string .= $c;
					$c = "";
				} elsif ($cr == 39 || $cr == 41 || $cr == 47
						|| $cr == 58 || $cr == 60 
						|| $cr == 61 || $cr == 62 
						|| $cr == 64 || $cr == 63) {
					$string .= $c;
					$c = "";				
				} elsif ($cr == 38) {	## '&'
						my $chrs = sprintf ("%c%s%s", 0x1B, "A", "S");
						$string .= $chrs;				
				} elsif ($cr == 33) {	## '!'
						my $chrs = sprintf ("%c%s%s", 0x1B, "S", "N");
						$string .= $chrs;				
				} elsif ($cr == 40) {
					$string .= ")";
					$c = "";									
				} elsif ($cr == 42) {
					$string .= "<";
					$c = "";									
				} elsif ($cr == 43) {
					if ($speed < 90) {
						$speed += 4;
						$setspeed = sprintf ("%c%c", 0x1C, $speed);
						$string .= $setspeed;
					}					
				} elsif ($cr == 45) {
					if ($speed > 8) {
						$speed -= 4;
						$setspeed = sprintf ("%c%c", 0x1C, $speed);
						$string .= $setspeed;
					}					
				} elsif ($cr == 0) {
					last;
				} 
				if ($debug > 1) {print $cr, "\n";}

			}
			
			if ($busy == 0) {
				if (length ($string) > 30) {
					$outstring = substr($string, 0, 30);
					$string = substr($string, 30);
					$count = $port->write($outstring);
				} elsif (length ($string) == 1) {
					$outstring = $string;
					$count = $port->write($outstring);
					$string = "";
				} else {
					$outstring = $string;
					$string = "";
					$count = $port->write($outstring);
				}
			} else {
					$outstring = $string;
					$string = "";
					$count = $port->write($outstring);				
			}
			
			if ($debug > 1) {print "WRITE:", $outstring, "\n";}
			
			$datagram = "";
		}
	}
	  
  ($count,$saw)=$port->read(1); # will read 1 char
        if ($count) {
				$stat = ord($saw);
				if ($stat > 191) {
					if ($debug > 1) {print "\n", $stat, "\n";}
					if (($stat & 1) == 1) {
						if ($debug){print "Buffer 2/3 full\n";}
					} elsif (($stat & 2) == 2) {
						if ($debug){print "Brk-in\n";}
					} elsif (($stat & 4) == 4) {
						if ($debug){print "Keyer busy\n";}
						`touch ~/.winkey/keyer_busy`;
						$busy = 1;
						$echo = "";
					} elsif (($stat & 8) == 8) {
						if ($debug){print "Tuning\n";}
					} elsif (($stat & 16) == 16) {
						if ($debug){print "Waiting\n";}
					} else {
						if ($debug){print "Idle\n";}
						if (-e "$ENV{HOME}/.winkey/keyer_busy") {
							`rm ~/.winkey/keyer_busy`;
						}
						$busy = 0;
						$echo = "";
					}
				} else { 
					if ($debug) {print $saw, "\n";}
					
					if ($busy && $string) {
						
						$echo .= $saw;
						
						if (length($echo) > 9) {
							if (length($echo) <= length($string)) {
								my $out = substr ($string, 0, length($echo));
								$string = substr ($string, length ($echo));
								$echo = "";
								$count = $port->write($out);
								$out = "";							
							} else {
								my $out = $string;
								$echo = "";
								$count = $port->write($out);
								$string = "";							
							}
						} else {
							my $out = $string;
							$echo = "";
							$count = $port->write($out);
							$string = "";
						}
					}
				}
        }
 }
 
	$keyerclose = sprintf ("%c%c", 0x00, 3);
   	$count = $port->write($keyerclose);
   	undef $port;
	exit;
}
 
