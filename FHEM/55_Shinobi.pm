#
#  93_Shinobi.pm 
#
package main;

use strict;
use warnings;
use HttpUtils;
use JSON;

# FHEM Modulfunktionen

sub Shinobi_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}    = "Shinobi_Define";
    $hash->{GetFn} = "Shinobi_Get";
    $hash->{AttrList} = "disable:1,0 prefix show_cmd hide_cmd";
    Log3 undef, 2, "Shinobi: Initialized new";
}

sub Shinobi_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};

    my @a = split("[ \t][ \t]*", $def);

    return "Usage: define devname Shinobi [http|https]://IP_or_Hostname:port apikey groupID " if (scalar(@a) < 4);

    $hash->{URL} = $a[2];
    $hash->{APIKEY} = $a[3];
    $hash->{GROUP} = $a[4];

    Log3 $name, 3, "Shinobi: [$name] defined";
}

sub Shinobi_HttpCallback($$$)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        Shinobi_HttpCallback_Error($hash,$name,$err);
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
            Shinobi_HttpCallback_Error($hash,$name,$shinobi_error);
        }
        elsif ( defined($http_error) )
        {
            Shinobi_HttpCallback_Error($hash,$name,$http_error);
        }
        else
        {
            # success
            my $json = decode_json($data);
            foreach (@{$json}) {
                my $prefix = AttrVal($name, "prefix", "");
                my $deviceName = makeDeviceName($prefix.$_->{name});
                my $error = AnalyzeCommand(undef, "define $deviceName ShinobiMonitor $_->{mid} $name");
                my $error = AnalyzeCommand(undef, "get $deviceName details");
            }
        }
    }
}

sub Shinobi_HttpCallback_Error($$$)
{
    my ($hash, $name, $err) = @_;

    Log3 $name, 1,"Shinobi: [$name] Error = $err";
}


sub Shinobi_Get($$@)
{
	my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	if($opt eq "monitors") {
        my $url = $hash->{URL}."/".$hash->{APIKEY}."/monitor/".$hash->{GROUP};

        my $reqpar = {
            url => $url,
            method => "GET",
            hideurl => 1,
            hash => $hash,
            callback => \&Shinobi_HttpCallback
        };

        HttpUtils_NonblockingGet($reqpar);
    }
	else
	{
		return "Unknown argument $opt, choose one of monitors";
	}
}


# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item helper
=item summary Provides access to the API of a Shinobi CCTV/NVR instance
=item summary_DE Bietet Zugriff auf die API einer Shinobi CCTV/NVR Instanz

=begin html

<a name="Shinobi"></a>
<h3>Shinobi</h3>
<ul>
    Module for using the API of a Shinobi CCTV/NVR instance.

    <a name="Shinobi_Define"></a>
    <h4>Define</h4>
	<ul>
		<code>define devname Shinobi [http|https]://IP_or_Hostname:port apikey groupID</code>
		<br /><br />Please ensure to use a permanent APIKEY to avoid goofs.
	</ul>

    <a name="Shinobi_Get"></a>
    <h4>Get</h4>
    <ul>
        <li><b>monitors</b>
        <code>get &lt;name&gt; monitors</code><br />
        Retrieves all configured monitors of the GROUP and creates according devices in FHEM if not yet existing.
        The name will be prefixed if configured via the attribute "prefix".
        </li>
    </ul>

    <a name="Shinobi_Attr"></a>
    <h4>Attributes</h4>
    <ul>
        disable:1,0
        <li><b>disable</b> <code>attr &lt;name&gt; disable [0|1]</code><br />
           no effect yet
       </li>
       <li><b>prefix</b> <code>attr &lt;name&gt; prefix PREFIX</code><br />
           Will be used on "get monitors" to prefix the names of the FHEM devices. Default is none.
       </li>
       <li><b>show_cmd</b> <code>attr &lt;name&gt; show_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set show" if not configured on monitor explicitly.
           See the ShinobiMonitor help for details.
       </li>
       <li><b>hide_cmd</b> <code>attr &lt;name&gt; hide_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set hide" if not configured on monitor explicitly.
           See the ShinobiMonitor help for details.
       </li>
    </ul>
</ul>

=end html

=begin html_DE

<a name="Shinobi"></a>
<h3>Shinobi</h3>
<ul>
    Module for using the API of a Shinobi CCTV/NVR instance.

    <a name="Shinobi_Define"></a>
    <h4>Define</h4>
	<ul>
		<code>define devname Shinobi [http|https]://IP_or_Hostname:port apikey groupID</code>
		<br /><br />Please ensure to use a permanent APIKEY to avoid goofs.
	</ul>

    <a name="Shinobi_Get"></a>
    <h4>Get</h4>
    <ul>
        <li><b>monitors</b>
        <code>get &lt;name&gt; monitors</code><br />
        Retrieves all configured monitors of the GROUP and creates according devices in FHEM if not yet existing.
        The name will be prefixed if configured via the attribute "prefix".
        </li>
    </ul>

    <a name="Shinobi_Attr"></a>
    <h4>Attributes</h4>
    <ul>
        disable:1,0
        <li><b>disable</b> <code>attr &lt;name&gt; disable [0|1]</code><br />
           no effect yet
       </li>
       <li><b>prefix</b> <code>attr &lt;name&gt; prefix PREFIX</code><br />
           Will be used on "get monitors" to prefix the names of the FHEM devices. Default is none.
       </li>
       <li><b>show_cmd</b> <code>attr &lt;name&gt; show_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set show" if not configured on monitor explicitly.
           See the ShinobiMonitor help for details.
       </li>
       <li><b>hide_cmd</b> <code>attr &lt;name&gt; hide_cmd COMMAND</code><br />
           A FHEM command that will be used by the monitors during "set hide" if not configured on monitor explicitly.
           See the ShinobiMonitor help for details.
       </li>
    </ul>
</ul>

=end html_DE

# Ende der Commandref
=cut