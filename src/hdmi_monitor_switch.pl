#!/usr/bin/perl
use warnings;
use strict;

######
#Input: Array of output candidates
#Output: Last enabled output
#####
sub _get_status
{
	my $drmdir="/sys/class/drm/";
	my $state=0;
	my @outputs=@_;
	my $xoutput="";
	foreach my $output (@outputs) {
		my $status="$drmdir$output/status";
		print("Looking $status\n");
		open(my $fh,'<',$status);
		while(<$fh>)
		{
			if ($_ eq "connected\n")
			{
				$state=1;
				my @xoutput=split(/-/,$output);
				$xoutput="$xoutput[1]-$xoutput[-1]";
				print("connected output to $xoutput\n");
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
	my @whodata=split(" ",$who[0]);
	$xdisplay= $whodata[-1] =~s/\(//r;
	$xdisplay= $xdisplay =~s/\)//r;
	$xuser=$whodata[0];
	return($xdisplay,$xuser);
}

############
#MAIN
###########
my $drmdir="/sys/class/drm/";
my ($XDISPLAY,$XUSER)=_get_session_data();
chomp(my $PATH_XRANDR=`/bin/which xrandr`);
my $XRANDR="nice -n 0 $PATH_XRANDR -d $XDISPLAY";
opendir(my $dh, $drmdir) || die "Couldn't open dir '$drmdir': $!";
my @cards = grep { (/card[0-9]-/) && -d "$drmdir/$_" }readdir($dh);
closedir $dh;
my @hdmi_outputs = grep { (/HDMI/) && -d "$drmdir/$_" } @cards;
@cards=grep {!/HDMI/} @cards;
my $hdmi=_get_status(@hdmi_outputs);
print("HDMI: $hdmi \n");
my $xoutput=_get_status(@cards);
my $cmd_auto="";
my $cmd_off="";
if ( $hdmi ne "" )
{
	print("Setting output to $hdmi\n");
	$cmd_auto="su -f  -c \"$XRANDR --output $hdmi --auto\" $XUSER";
	$cmd_off="su -f  -c \"$XRANDR --output $xoutput --off\" $XUSER";
} elsif ( $xoutput ne "") {
	print("Setting output to $xoutput\n");
	$cmd_auto="su -f  -c \"$XRANDR --output $xoutput --auto\" $XUSER";
} else {
	print("No outputs detected!!!\n");
}
if ($cmd_off ne "")
{
	my $pid=fork();
	if ($pid==0)
	{
		exec($cmd_off);
		exit(1);
	}
}
my $pid_auto=fork();
if ($pid_auto==0)
{
	exec($cmd_auto);
	exit(1);
}
exit(0)
