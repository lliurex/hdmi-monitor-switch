#!/usr/bin/perl
use warnings;
use strict;
use Fcntl qw(O_RDWR O_CREAT);
#use autodie; # Debug purposes

#GLOBAL VARS
my $drmdir="/sys/class/drm/";
my $USER=$ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
my $logfile="/tmp/.hdmi_switch_".$USER.".log";

#########
#SUBS
########

#######
#Input: Debug msg (string)
######
sub _log
{
	open(my $fh,">>",$logfile);
	print($fh "@_\n");
	close($fh);
}

######
#Input: Array of output candidates
#Output: Last enabled output
#####
sub _get_status
{
	my $state=0;
	my @outputs=@_;
	my $xoutput="";
	foreach my $output (@outputs) {
		my $status="$drmdir$output/status";
		_log("Looking $status");
		open(my $fh,'<',$status);
		while(<$fh>)
		{
			if ($_ eq "connected\n")
			{
				$state=1;
				my @xoutput=split(/-/,$output);
				$xoutput="$xoutput[1]-$xoutput[-1]";
				_log("connected output to $xoutput");
			}
		}
		close($fh);
		my $stat="$drmdir$output/status";
	}
	return($xoutput);
}

#####
#Input: 
#Output: Display and user logged in a tty
#####
sub _get_session_data
{
	my $xdisplay="";
	my $xuser="";
	my @who=grep {(/tty.*\(:[0-9]*\)/)}`who`;
	if (scalar(@who)>0)
	{
		my @whodata=split(" ",$who[0]);
		$xuser=$whodata[0];
		$xdisplay= $whodata[-1] =~s/\(//r;
		$xdisplay= $xdisplay =~s/\)//r;
	}
	return($xdisplay,$xuser);
}

#####
#Input: 
#Output: xauth and user of Xorg process
#####
sub _get_sddm_data
{
	my $xdisplay="";
	my $xuser="";
	my $xauth="";
	#get values from ps
	my @ps=grep {(/root.*X.*sddm/)}`ps -ef`;
	if (scalar(@ps)>0)
	{
		my @psline=split(/ /,$ps[0]);
		$xuser=$psline[0];
		my ($index) = grep { $psline[$_] ~~ "-auth" } 0 .. $#psline;
		$xauth=$psline[$index+1];
	}
	return($xauth,$xuser);
}


#####
#Input: Xauthority, xrandr full path, hdmi device (cardX-hdmi) 
#Output: xauth and user of Xorg process
#####
sub _get_resolution_for_output
{
	my ($XAUTH,$XRAND,$HDMI)=@_;
	my $XRES="";
	$ENV{XAUTHORITY}=$XAUTH;
	my @xinfo=`$XRAND -d :0`;
	my $sw_print=0;
	foreach my $line (@xinfo)
	{
		if ($sw_print)
		{
			my @line=split(" ",$line);
			_log("RES: $line[0]");
			$XRES=$line[0];
			last;
		}
		if ($line=~/$HDMI connected/ )
		{
			$sw_print=1;
		}

	}
	return($XRES);
}


############
#MAIN
###########

#Get cards
opendir(my $dh, $drmdir) || die "Couldn't open dir '$drmdir': $!";
my @cards = grep { (/card[0-9]-/) && -d "$drmdir/$_" }readdir($dh);
closedir $dh;
my @hdmi_outputs = grep { (/HDMI/) && -d "$drmdir/$_" } @cards;
@cards=grep {!/HDMI/} @cards;
my $hdmi=_get_status(@hdmi_outputs);
_log("HDMI: $hdmi");

#Get active cards
my $xoutput=_get_status(@cards);

#Get data
my ($XDISPLAY,$XUSER)=_get_session_data();
my ($XAUTHORITY,$SDDMUSER)=_get_sddm_data();
chomp(my $PATH_XRANDR=`/bin/which xrandr`);
my $XRANDR="$PATH_XRANDR -d $XDISPLAY";
_log("USER: $XUSER");


my $cmd_auto=""; #cmd to execute
my $cmd_sddm=""; #command printed to stdout for XbrSetup
my $cmd_off=""; #poweroff command
my $print_cmd=0; #check need to print result
if ($XUSER)
{
	if ( $hdmi ne "" )
	{
		_log("Setting output to $hdmi");
		$cmd_auto="su -f  -c \"$XRANDR --output $hdmi --primary\" $XUSER";
		$cmd_off="su -f  -c \"$XRANDR --output $xoutput --off\" $XUSER";
	} elsif ( $xoutput ne "") {
		 _log("Setting output to $xoutput");
		$cmd_auto="su -f  -c \"$XRANDR --output $xoutput --auto\" $XUSER";
	} else {
		_log("No outputs detected!!!");
	}
} elsif ( $hdmi ne "" ){
	$XRANDR="/usr/bin/xrandr";
	my $XRES=_get_resolution_for_output($XAUTHORITY,$XRANDR,$hdmi);
	$print_cmd=2;
	#get max res of display
	$cmd_off="$XRANDR --output $xoutput --off -d :0";
	#$cmd_auto="$XRANDR --output $hdmi --auto --fb $XRES --output $hdmi --primary --output $xoutput --off -d :0";
	$cmd_auto="$XRANDR --output $hdmi --auto --fb $XRES -d :0";
	$cmd_sddm="XAUTHORITY=$XAUTHORITY $XRANDR --output $hdmi --primary --fb $XRES --output $xoutput --off -d :0";
} else {
	$XRANDR="/usr/bin/xrandr";
	$print_cmd=1;
	$cmd_auto="$XRANDR --output $xoutput --auto -d :0";

}
if ($cmd_off ne "")
{
	_log("OFF: $cmd_off");
	my $pid=fork();
	if ($pid==0)
	{
		system($cmd_off);
		exit(0);
	}
}
_log("ON: $cmd_auto");
if ($print_cmd==0)
{
	my $pid=fork();
	if ($pid==0)
	{
		system($cmd_auto);
		exit(0);
	}
} else {
	_log("SDDM: $cmd_sddm");
	if ($cmd_auto ne "")
	{
		my $pid=fork();
		if ($pid==0)
		{
			$ENV{XAUTHORITY}=$XAUTHORITY;
			system("$cmd_auto") or _log (%ENV);
			exit(0);
		}
	}
	print($cmd_sddm);
}
_log("Switch ended");
exit(0)
