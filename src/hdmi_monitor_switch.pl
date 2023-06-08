#!/usr/bin/perl
use warnings;
use strict;
use Fcntl qw(O_RDWR O_CREAT);
my $drmdir="/sys/class/drm/";
my $USER=$ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
my $logfile="/tmp/.hdmi_switch_".$USER.".log";
sysopen(my $F,$logfile,O_RDWR|O_CREAT,0666);
print($F "");
close($F);
chmod(0777,$logfile) || _log("chmod failed");

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
	my @psline=split(/ /,$ps[0]);
	$xuser=$psline[0];
	my ($index) = grep { $psline[$_] ~~ "-auth" } 0 .. $#psline;
	$xauth=$psline[$index+1];
	return($xauth,$xuser);
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
chomp(my $PATH_XRANDR=`/bin/which xrandr`);
my $XRANDR="$PATH_XRANDR -d $XDISPLAY";
my $cmd_auto="";
my $cmd_auto2="";
my $cmd_print="";
my $cmd_off="";
my $print_cmd=0;
_log("USER: $XUSER");
if ($XUSER)
{
	if ( $hdmi ne "" )
	{
		_log("Setting output to $hdmi");
		$cmd_auto="su -f  -c \"$XRANDR --output $hdmi --auto\" $XUSER";
		$cmd_off="su -f  -c \"$XRANDR --output $xoutput --off\" $XUSER";
	} elsif ( $xoutput ne "") {
		 _log("Setting output to $xoutput");
		$cmd_auto="su -f  -c \"$XRANDR --output $xoutput --auto\" $XUSER";
	} else {
		_log("No outputs detected!!!");
	}
	if ($cmd_off ne "")
	{
		my $pid=fork();
		if ($pid==0)
		{
			_log("Switch off");
			_log("$cmd_off");
			exec($cmd_off) or die;
			exit(1);
		}
	}
	my $pid_auto=fork();
	if ($pid_auto==0)
	{
		exec($cmd_auto);
		exit(1);
	}
} elsif ( $hdmi ne "" ){
	my ($XAUTHORITY,$XUSER)=_get_sddm_data();
	$XRANDR="/usr/bin/xrandr";
	my $XRES="1920x1080";
	$print_cmd=2;
	#get max res of display
	$cmd_auto="XAUTHORITY=$XAUTHORITY $XRANDR --output $xoutput --off -d :0";
	$cmd_auto2="XAUTHORITY=$XAUTHORITY $XRANDR --output $hdmi --primary -s $XRES -d :0";
	$cmd_print="XAUTHORITY=$XAUTHORITY $XRANDR --output $hdmi --primary --output $xoutput --off -d :0";
} else {
	my ($XAUTHORITY,$XUSER)=_get_sddm_data();
	$XRANDR="/usr/bin/xrandr";
	$print_cmd=1;
	$cmd_auto="XAUTHORITY=$XAUTHORITY $XRANDR --output $xoutput --auto -d :0";

}
_log("$cmd_auto");
_log("$cmd_off");
if ($cmd_off ne "")
{
	my $pid=fork();
	if ($pid==0)
	{
		exec($cmd_off);
		exit(1);
	}
}
if ($print_cmd==0)
{
	my $pid_auto=fork();
	if ($pid_auto==0)
	{
		exec($cmd_auto);
		exit(1);
	}
} elsif ($print_cmd==2) {
	print($cmd_print);
	system($cmd_auto2);
	exec($cmd_auto);
} else {
	print($cmd_auto);
	exec($cmd_auto);
}

exit(0)
