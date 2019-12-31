# $Id: 98_livetrackingconn.pm $$$
#
##############################################################################

package main;
use strict;
use warnings;

sub livetrackingconn_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}            =   "livetrackingconn_Define";
  $hash->{UndefFn}          =   "livetrackingconn_Undefine";
  $hash->{AttrFn}           =   "livetrackingconn_Attr";
  $hash->{NotifyFn}         =   "livetrackingconn_Notify";
  $hash->{NotifyOrderPrefix}=   "999-";
  $hash->{AttrList}         =   "livetrackingDevice ".
                                "homeradius wayhomeradius goneradius leavetounderway:0,1 ".
                                $readingFnAttributes;
}

sub livetrackingconn_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{NOTIFYDEV} = "TYPE=livetracking";
  $hash->{STATE} = "Initialized";
  return undef;
}

sub livetrackingconn_Undefine($$) {
  my ($hash, $arg) = @_;
  return undef;
}

sub livetrackingconn_Attr(@) {
  my ($cmd, $name, $attr, $val) = @_;
  my $hash = $defs{$name};
  if ($attr && $attr eq 'livetrackingDevice') {
  	if ($cmd eq "del") {
		#notifyRegexpChanged($hash, "TYPE=livetracking");
		$hash->{NOTIFYDEV} = "TYPE=livetracking";
	} elsif ($cmd eq "set") {
		my @devs = devspec2array($val);
		return "livetrackingconn ($name): wrong devspec $val" if (scalar @devs == 1 && not exists $defs{$devs[0]});
		$hash->{NOTIFYDEV} = $val;
		#notifyRegexpChanged($hash, $val);
		foreach my $dev (@devs) {
			Log3 $hash->{NAME}, 3, "livetrackingconn $hash->{NAME}: Found livetrackingDevice $dev";
			addToDevAttrList($dev, "homeradius");
			addToDevAttrList($dev, "wayhomeradius");
			addToDevAttrList($dev, "goneradius");
			addToDevAttrList($dev, "leavetounderway:0,1");
		}
	}
  }
  return undef;
}

sub livetrackingconn_Notify($$)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  my $devName = $dev->{NAME};

  Log3 ($name, 5, "$hash->{NAME}: Notify from ".$devName);
  
  my $events = deviceEvents($dev,1);
  return if( !$events );

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));
	Log3 ($name, 5, "$hash->{NAME}: Notify from ".$devName . ": " .$event);
	#next if (substr($event, 0, 8) ne "distance" && substr($event, 0, 4) ne "zone");
	next if (substr($event, 0, 8) ne "distance" && substr($event, 0, 5) ne "enter" && substr($event, 0, 5) ne"leave");
	Log3 ($name, 4, "$hash->{NAME}: Notify from ".$devName . ": " .$event . " -> using it");
	livetrackingconn_residents($hash,$event,$devName);
  }
  return undef;
}

sub livetrackingconn_residents($$$) {
	my ($hash,$dataset,$devName) = @_;
	my ($rname,$rvalue) = split(': ', $dataset);
	
	my $deviceAlias = "";
    # Find ROOMMATE and GUEST devices associated with this device UUID via Attr rr_geofenceUUIDs
    delete $hash->{ROOMMATES};
	delete $hash->{GUESTS};
	delete $hash->{PET};
    foreach my $gdev ( devspec2array("rr_geofenceUUIDs=.+,rg_geofenceUUIDs=.+,rp_geofenceUUIDs=.+") ) {
		foreach my $restype ("ROOMMATE","GUEST") {
			next unless ( IsDevice( $gdev, $restype ) );
			Log3 $hash->{NAME}, 5, "$hash->{NAME} : Checking r*_geofenceUUIDs for $gdev";
			$hash->{($restype . "S")} .= ",$gdev" if $hash->{($restype . "S")};
			$hash->{($restype . "S")} = $gdev if !$hash->{($restype . "S")};
			foreach (split( ',', AttrVal( $gdev, "rr_geofenceUUIDs", AttrVal( $gdev, "rg_geofenceUUIDs", AttrVal( $gdev, "rp_geofenceUUIDs", undef ) ) ) )) {
				if ( $_ eq $devName ) {
					Log3 $hash->{NAME}, 3, "$hash->{NAME}: " ."Found matching UUID at $restype device $gdev";
					$deviceAlias      = $gdev;
					last;
				}
			}			
		}
    }
	# Update location info in associated ROOMMATE and GUEST device 
	if ( IsDevice( $deviceAlias, "ROOMMATE|GUEST|PET" ) ) {
		#  Attribute homeradius exists and MQTT telegram type is location
		if ( $rname eq "enter" || $rname eq "leave" ) {
	  # enter und leave nutzen
			my $locName = $rvalue;
			my $trigger = ($rname eq "enter" ? 1 : 0);
		  # #####..#.#.#.#.
			unless ($trigger || AttrVal( $devName, "leavetounderway", AttrVal( $hash->{NAME}, "leavetounderway", 0 ) ) != 0) {
				$locName = "underway";
				Log3 $hash->{NAME}, 4, "$hash->{NAME}: " . "Verlassen zu underway";
			}
			Log3 $hash->{NAME}, 4, "$hash->{NAME}: " . "location = $locName, Trigger = $trigger";
		  # publish Zonenames as location
			livetrackingconn_setresidents($deviceAlias, $locName, $trigger, $devName);		
		} elsif ( substr($rname, 0, 4) eq "zone" && (my $hradius = AttrVal( $devName, "homeradius", AttrVal( $hash->{NAME}, "homeradius", "0" ) )) == 0) {
	  # INAKTIV
	  # Reading of type zone.* received and attribute homeradius does not exist in livetracking device
			my $locName = AttrVal( $devName, "zonename_".(split "_", $rname)[1], undef ) || ReadingsVal( $devName, "place", "-" );
			my $trigger = ($rvalue eq "active" ? 1 : 0);
			Log3 $hash->{NAME}, 4, "$hash->{NAME}: " . "location = $locName $rvalue , Trigger = $trigger";
		  # publish Zonenames as location
			livetrackingconn_setresidents($deviceAlias, $locName, $trigger, $devName);

		} elsif ( $rname eq "distance" && ($hradius = AttrVal( $devName, "homeradius", AttrVal( $hash->{NAME}, "homeradius", "0" ) )) > 0 ) {
	  # Reading of type distance received and attribute homeradius exists (attribute in livetracking device overrules attribute in livetrackingconn)
			my $locname = "underway";
			my $locaway = 1;
			my $trigger = 1;
			my $homedist = ($rvalue * 1000 ) - ( ReadingsVal( $devName, "accuracy", 1000 ) / 2 ) ;
			if ( $homedist <= $hradius ) {
		  # Reading of type distance ist smaller than attribute homeradius (attribute in livetracking device overrules attribute in livetrackingconn)
				$locname = "home";
				$locaway = 0;
			} elsif ( $homedist <= (my $wradius = AttrVal( $devName, "wayhomeradius", AttrVal( $hash->{NAME}, "wayhomeradius", "0" ) )) ) {
		  # Reading of type distance ist smaller than attribute wayhomeradius (attribute in livetracking device overrules attribute in livetrackingconn)
				if ( ReadingsVal( $hash->{NAME}, "away_" . $devName, "0" ) == 1 && ReadingsVal( $deviceAlias, "wayhome", "0" ) == 0 ) {
					$locname = "wayhome";
				}
				$locaway = 0;
			} elsif ( $homedist >= AttrVal( $devName, "goneradius", AttrVal( $hash->{NAME}, "goneradius", 100000000 ) ) ) {
				fhem "set $deviceAlias gone";
			}
			readingsSingleUpdate($hash, "away_" . $devName, $locaway, 0);		
			Log3 $hash->{NAME}, 4, "$hash->{NAME}: " . "location = $locname, Trigger = $trigger, locaway: $locaway";
		  # publish home|wayhome|underway as location
			livetrackingconn_setresidents($deviceAlias, $locname, $trigger, $devName);
		}
	}
	return undef
}
# trigger update of resident device readings ROOMMATE and GUEST device
sub livetrackingconn_setresidents(@) {
	my ($deviceAlias, $locname, $trigger, $devName) = @_;
	my $id = ReadingsVal( $devName, "id", $devName );
	my $timestamp = ReadingsTimestamp( $devName, "location", undef );
	my ($lat,$long) = split(",",ReadingsVal( $devName, "location", "-,-" ));
	my $address = CommandGet(undef,$devName." address");
	my $radius = ReadingsVal( $devName, "accuracy", undef );
	RESIDENTStk_SetLocation( $deviceAlias, $locname, $trigger, $id, $timestamp, 
								 $lat, $long, $address, $devName, $radius, $lat, $long, $address );	
}
##########################
#sub RESIDENTStk_SetLocation(
# $name,       $location,      $trigger,     $id,		$time,       $lat,           $long,        $address,
# $device,     $radius,        $posLat,      $posLong,	$posAddress, $posBeaconUUID, $posDistHome, $posDistLoc,
# $motion,     $wifiSSID,      $wifiBSSID)
1;

=pod
=item device
=item summary connector between livetracking and RESIDENTS
=item summary_DE connector zwischen livetracking und RESIDENTS
=begin html

<a name="livetrackingconn"></a>
<h3>livetrackingconn</h3>
<ul>
  This modul acts a an connector between livetracking and RESIDENTS devices.<br><br>
  By default (not attribute homeradius set) zonename_x will be reported to connected <a href="#ROOMMATE">ROOMMATE</a> or <a href="#GUEST">GUEST</a> 
  device and evaluated via rr_locationHome and rr_locationUnderway. Attributes homeradius, wayhomeradius, goneradius and leavetounderway can also be set directly in livetracking definitions which are selected via
  owntracksDevice attribute. Attributes set in owntracksDevice will supersede the ones from livetrackingconn device
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt;</code>
    <br>
  </ul><br>
  
   <b>Attributes</b>
   <ul>
	  <li><a name="livetrackingDevice">livetrackingDevice</a><br>
		<a href="#devspec">devspec</a> of <a href="#livetracking">livetracking</a> devices which<br>
		shall connected to an <a href="#ROOMMATE">ROOMMATE</a>, <a href="#GUEST">GUEST</a> or <a href="#PET">PET</a></a> device<br>
		The attribute rr_geofenceUUIDs/rg_geofenceUUIDs/rp_geofenceUUIDs on this devices must be also set to the name of the corresponding <a href="#livetracking">livetracking</a> device<br>
		default: TYPE=livetracking
		</li><br>
	  <li><a name="homeradius">homeradius</a><br>
		radius in meters<br>
		if existing and smaller than distance reading, 
		home will be reported to connected device 
		</li><br>
	  <li><a name="wayhomeradius">wayhomeradius</a><br>
	  	radius in meters<br>
		can be defined aditionally to and has to be greater than homeradius<br>
		if existing and smaller than distance reading, 
		wayhome will be reported to connected device<br>
		</li><br>
	  <li><a name="goneradius">goneradius</a><br>
	  	radius in meters<br>
		if existing and smaller than distance reading, 
		gone will be reported to connected device<br>
		</li><br>
	  <li><a name="leavetounderway">leavetounderway</a><br>
	  	Set Location to underway on Zone exit<br>
		If set, Reading location in RESIDENTS Device will set to underway, as soon as <a href="#livetracking">livetracking</a> device left a Zone.<br>
		Attribut homeradius must not set for this function.<br>
		</li><br>
 	  <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>
</div>
=end html

=begin html_DE

<a name="livetrackingconn"></a>
<h3>livetrackingconn</h3>
<ul>
  Mit Hilfe dieses Moduls l&auml;sst sich ein livetracking Device in einem RESIDENTS device nutzen<br><br>
  Ohne weitere Konfiguration (Attribut homeradius nicht gesetzt) wird zonename_x als location an entsprechende <a href="#ROOMMATE">ROOMMATE</a> oder <a href="#GUEST">GUEST Devices gesendet</a> 
  und gegen rr_locationHome und rr_locationUnderway gepr&uuml;ft. Die Attribute homeradius, wayhomeradius, goneradius und leavetounderway können auch in den livetracking Definitionen, die &uuml;ber das Attribut
  owntracksDevice verbunden sind, separat gesetzt werden Diese Attribut überschreibt dann die Attributdefinition im livetrackingconn Device.
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt;</code>
    <br>
  </ul><br>
  
   <b>Attribute</b>
   <ul>
	  <li><a name="livetrackingDevice">livetrackingDevice</a><br>
		Name der <a href="#livetracking">livetracking</a> Devices die mit einem<br>
		<a href="#ROOMMATE">ROOMMATE</a>, <a href="#GUEST">GUEST</a> oder <a href="#PET">PET</a> Device verbunden werden sollen.<br>
		Das Attribut rr_geofenceUUIDs/rg_geofenceUUIDs/rp_geofenceUUIDs dieser Devices muss ebenso den Namen des entsprechenden <a href="#livetracking">livetracking</a> Devices enthalten.<br>
		default: TYPE=livetracking
		</li><br>
	  <li><a name="homeradius">homeradius</a><br>
		Radius in Metern<br>
		Im RESIDENTS Device wird das Reading location auf home gesetzt, wenn diese Attribut existiert <br>
		und kleiner als das Reading distance im <a href="#livetracking">livetracking</a> device ist.<br>
		</li><br>
	  <li><a name="wayhomeradius">wayhomeradius</a><br>
	  	Radius in Metern<br>
		Kann zus&auml;tzlich zum Attribut homeradius definiert werden und mu&szlig; gr&ouml;&szlig;er als dieses sein.<br>
		Im RESIDENTS Device wird das Reading location auf wayhome gesetzt, wenn diese Attribut existiert<br>
		und kleiner als das Reading distance im <a href="#livetracking">livetracking</a> device ist.<br>
		</li><br>
	  <li><a name="goneradius">goneradius</a><br>
	  	Radius in Metern<br>
		Im RESIDENTS Device wird das Reading location auf gone gesetzt, wenn diese Attribut existiert<br>
		und kleiner als das Reading distance im <a href="#livetracking">livetracking</a> device ist.<br>
		</li><br>
	  <li><a name="leavetounderway">leavetounderway</a><br>
	  	Location auf underway setzen wenn eine Zone Verlassen wird<br>
		Wenn gesetzt, wird im RESIDENTS Device das Reading location auf underway gesetzt, sobald das <a href="#livetracking">livetracking</a> device sich in keiner Zone mehr befindet.<br>
		Attribut homeradius darf f&uuml;r diese Funktion nicht gesetzt werden.<br>
		</li><br>
 	  <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>
</div>
=end html_DE

=cut