#
#  93_ShinobiMonitor.pm 
#
package main;

use strict;
use warnings;
use HttpUtils;
use JSON;

# FHEM Modulfunktionen

my $ShinobiMonitor_LastShower = undef;

sub ShinobiMonitor_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}    = "ShinobiMonitor_Define";
    $hash->{SetFn} = "ShinobiMonitor_Set";
    $hash->{GetFn} = "ShinobiMonitor_Get";
    $hash->{SetDetailsFn} = "ShinobiMonitor_SetDetails";
    $hash->{AttrList} = "disable:1,0 show_cmd hide_cmd";
    Log3 undef, 2, "ShinobiMonitor: Initialized new";
}

sub ShinobiMonitor_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};

    my @a = split("[ \t][ \t]*", $def);

    return "Usage: define devname ShinobiMonitor monitorID ioDEV" if (scalar(@a) < 2);

    $hash->{MONITOR} = $a[2];
    AssignIoPort($hash, $a[3]);

    Log3 $name, 3, "ShinobiMonitor: [$name] defined";
}

sub ShinobiMonitor_DetailsHttpCallback($$$)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        ShinobiMonitor_HttpCallback_Error($hash,$name,$err);
    }
    else {
        my $header = $param->{httpheader};
        my $http_error = undef;
        my $shinobi_error = undef;
        while ($header =~ /HTTP\/1\.0\s*([4|5]\d\d\s*.*+)/g) {
            $http_error = $1;
        }

        if ( defined($shinobi_error) )
        {
            ShinobiMonitor_HttpCallback_Error($hash,$name,$shinobi_error);
        }
        elsif ( defined($http_error) )
        {
            ShinobiMonitor_HttpCallback_Error($hash,$name,$http_error);
        }
        else
        {
            # success
            my $json = decode_json($data);
            my $details =$json->[0];
            ShinobiMonitor_SetDetails($hash,$details)
        }
    }
}

sub ShinobiMonitor_HttpCallback($$$)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        ShinobiMonitor_HttpCallback_Error($hash,$name,$err);
    }
    else {
        my $header = $param->{httpheader};
        my $http_error = undef;
        my $shinobi_error = undef;
        while ($header =~ /HTTP\/1\.0\s*([4|5]\d\d\s*.*+)/g) {
            $http_error = $1;
        }

        readingsSingleUpdate($hash, "last_response",  $data, 1);

        if ( defined($shinobi_error) )
        {
            ShinobiMonitor_HttpCallback_Error($hash,$name,$shinobi_error);
        }
        elsif ( defined($http_error) )
        {
            ShinobiMonitor_HttpCallback_Error($hash,$name,$http_error);
        }
        else
        {
            # success

        }
    }
}

sub ShinobiMonitor_HttpCallback_Error($$$)
{
    my ($hash, $name, $err) = @_;

    Log3 $name, 1,"ShinobiMonitor: [$name] Error = $err";
}

sub ShinobiMonitor_SetDetails($$)
{
    my ($hash, $details) = @_;

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "name", $details->{name});
    readingsBulkUpdate($hash, "mode", $details->{mode});
    readingsBulkUpdate($hash, "type", $details->{type});
    readingsBulkUpdate($hash, "protocol", $details->{protocol});
    readingsBulkUpdate($hash, "host", $details->{host});
    readingsBulkUpdate($hash, "port", $details->{port});
    readingsBulkUpdate($hash, "path", $details->{path});
    readingsBulkUpdate($hash, "status", $details->{status});
    readingsBulkUpdate($hash, "stream", $hash->{IODev}->{URL}.$details->{streams}[0]);

    readingsEndUpdate($hash, 1);
}

sub ShinobiMonitor_Get($$@)
{
	my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	if($opt eq "details") {
        my $url = $hash->{IODev}->{URL}."/".$hash->{IODev}->{APIKEY}."/monitor/".$hash->{IODev}->{GROUP}."/".$hash->{MONITOR};

        my $reqpar = {
            url => $url,
            method => "GET",
            hideurl => 1,
            hash => $hash,
            callback => \&ShinobiMonitor_DetailsHttpCallback
        };

        HttpUtils_NonblockingGet($reqpar);
    }
	else
	{
		return "Unknown argument $opt, choose one of details";
	}
}

sub ShinobiMonitor_Set($$@)
{
    my ( $hash, $name, $cmd, @args ) = @_;
    Log3 $name, 5, "ShinobiMonitor: [$name] set $cmd";

    if ( lc $cmd eq 'record' ) {
        my $duration = $args[0];
        ShinobiMonitor_StartRecording($hash, $name, $duration);

        return (undef,1);
    }
    elsif ( lc $cmd eq 'event' ) {
        my $room = $args[0];
        my $reason = $args[1];
        ShinobiMonitor_TriggerEvent($hash,$room,$reason);
        return (undef,1);
    }
    elsif ( lc $cmd eq 'show' ) {
        my $show_cmd = AttrVal($name, "show_cmd", undef);
        if ( !defined($show_cmd) )
        {
            $show_cmd = AttrVal($hash->{IODev}->{NAME}, "show_cmd", undef);
        }
        if ( defined($show_cmd) )
        {
            RemoveInternalTimer($hash, "ShinobiMonitor_Hide");
            $ShinobiMonitor_LastShower = $name;
            $show_cmd =~ s/\$STREAM/ReadingsVal($name,"stream",0)/eig;
            $show_cmd =~ s/\$NAME/$name/eig;
            AnalyzeCommandChain(undef, $show_cmd);
            if (scalar(@args) > 0) {
                InternalTimer(gettimeofday() + $args[0], "ShinobiMonitor_Hide", $hash);
            }
        }
        return (undef,1);
    }
    elsif ( lc $cmd eq 'hide' ) {
        $ShinobiMonitor_LastShower = $name;
        ShinobiMonitor_Hide($hash);
        return (undef,1);
    }
    else {
        return "Unknown argument $cmd, choose one of record event show hide";
    }
}

sub ShinobiMonitor_Hide($)
{
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    if ($name ne $ShinobiMonitor_LastShower) {
        Log3 $name, 5, "ShinobiMonitor: [$name] Ignoring hide timer of someone else";
        return;
    }

    Log3 $name, 4, "ShinobiMonitor: [$name] Hide";

    my $hide_cmd = AttrVal($name, "hide_cmd", undef);
    if ( !defined($hide_cmd) )
    {
        $hide_cmd = AttrVal($hash->{IODev}->{NAME}, "hide_cmd", undef);
    }
    if ( defined($hide_cmd) )
    {
        $hide_cmd =~ s/\$STREAM/ReadingsVal($name,"stream",0)/eig;
        $hide_cmd =~ s/\$NAME/$name/eig;
        AnalyzeCommandChain(undef, $hide_cmd);
    }
}

sub ShinobiMonitor_StartRecording($$$)
{
    my ($hash, $name, $duration) = @_;
    my $url = $hash->{IODev}->{URL}."/".$hash->{IODev}->{APIKEY}."/monitor/".$hash->{IODev}->{GROUP}."/".$hash->{MONITOR}."/record/".$duration;

    my $reqpar = {
        url => $url,
        method => "GET",
        hideurl => 1,
        hash => $hash,
        callback => \&ShinobiMonitor_HttpCallback
    };

    Log3 $name, 4, "ShinobiMonitor: [$name] Start recording";
    HttpUtils_NonblockingGet($reqpar);
}

sub ShinobiMonitor_TriggerEvent($$$)
{
    my ($hash, $room ,$reason) = @_;
    my $name = $hash->{NAME};
    my $url = $hash->{IODev}->{URL}."/".$hash->{IODev}->{APIKEY}."/motion/".$hash->{IODev}->{GROUP}."/".$hash->{MONITOR}."?data={\"plug\":\"$name\",\"name\":\"$room\",\"reason\":\"$reason\",\"confidence\":100.0}";

    my $reqpar = {
        url => $url,
        method => "GET",
        hideurl => 1,
        hash => $hash,
        callback => \&ShinobiMonitor_HttpCallback
    };

    Log3 $name, 4, "ShinobiMonitor: [$name] Trigger motion";
    HttpUtils_NonblockingGet($reqpar);
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item helper
=item summary The ShinobiMonitor
=item summary_DE Der ShinobiMonitor

=begin html

<a name="ShinobiMonitor"></a>
<h3>ShinobiMonitor</h3>
<ul>
    Module for using the monitor API of a Shinobi CCTV/NVR instance.

    <a name="ShinobiMonitor_Define"></a>
    <h4>Define</h4>
	<ul>
		<code>define devname Shinobi [http|https]://IP_or_Hostname:port apikey groupID</code>
		<br /><br />Please ensure to use a permanent APIKEY to avoid goofs.
	</ul>

    <a name="ShinobiMonitor_Get"></a>
    <h4>Get</h4>
    <ul>
        <li><b>details</b>
        <code>get &lt;name&gt; details</code><br />
        Gets the latest details of the monitor. Use this to update the readings manually. The readings are not updated automatically.
        </li>
    </ul>

    <a name="ShinobiMonitor_Set"></a>
    <h4>Set</h4>
    <ul>
        <li><b>record</b>
        <code>set &lt;name&gt; record SEC</code><br />
        Puts the monitor in record state for number of seconds provided. <a href="https://shinobi.video/docs/api#content-set-to-a-mode-for-a-number-of-minutes-to-elapse-before-automatically-stops">link</a>
        </li>
        <li><b>event</b>
        <code>set &lt;name&gt; event REGION REASON</code><br />
        Creates a motion trigger on the monitor. Note that the handling of triggers needs to be configured on each monitor. <a href="https://shinobi.video/docs/api#content-trigger-a-motion-event">link</a>
        Use this to publish FHEM events of motion or door sensors to Shinobi.
        </li>
        <li><b>show</b>
        <code>set &lt;name&gt; show [SEC]</code><br />
        Executes the configured CMD in the attribute "show_cmd" of this monitor or if missing the parent IODev. The keyword $STREAM and $NAME will be replaced with according reading.
        Use this to display the stream on tablets or TVs that you have configured in FHEM.
        You can optionally provide the number of seconds to automatically hide the stream again.
        </li>
        <li><b>hide</b>
        <code>set &lt;name&gt; hide</code><br />
        Immediatlly calls the CMD in the attribute "hide_cmd" of this monitor or if missing the parent IODev. The keyword $STREAM and $NAME will be replaced with according reading.
        Use this to end the stream on tablets or TVs that you have configured in FHEM.
        </li>

    </ul>

    <a name="ShinobiMonitor_Attr"></a>
    <h4>Attributes</h4>
    <ul>
        disable:1,0
        <li><b>disable</b> <code>attr &lt;name&gt; disable [0|1]</code><br />
           no effect yet
       </li>
       <li><b>show_cmd</b> <code>attr &lt;name&gt; show_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set show". Can be configured globally on the IODev.
           See the show setter help for details.
       </li>
       <li><b>hide_cmd</b> <code>attr &lt;name&gt; hide_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set hide". Can be configured globally on the IODev.
           See the hide setter help for details.
       </li>
    </ul>
</ul>

=end html

=begin html_DE

<a name="ShinobiMonitor"></a>
<h3>ShinobiMonitor</h3>
<ul>
</ul>

=end html_DE

# Ende der Commandref
=cut