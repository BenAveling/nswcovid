#!/usr/bin/perl -w

# ######################################################################

#   Copyright (C) 2021-22  Ben Aveling

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.

# ######################################################################
# This script creates a google maps html page that shows
# recent cases in each LGA or Postcode
#
# FIXME: We have lots of mystery suburbs that don't map to LGA. :-/
# FIXME: One of our 'LGAs' is the collective correctional system.
# This possibly breaks multiple unconscious assumptions.
# But (except briefly), the cases in Justice Health don't have an LGA
# e.g. 2020-07-29,,,Justice Health,,
# So have arbitrarily put Justice Health at
# -33.98968356474387, 151.319736391778 (i.e. Botany Bay)
# ######################################################################

my $usage = qq{Usage:
  perl plot.pl [-l] [-d num_days]

  -l output is for local use only
  -d show num_days worth of days [instead of the default 90]

Note: Input and output files are currently hardcoded.
};
# ######################################################################
# History:
# 2021-08-01 Created.
# 2021-07-25 new option: -d
# 2021-09-04 Added vax % 
#            Removed one popup - leaving only the 'marker'
# 2022-02-08 Changed the scale (thanks Omicron)
# 2022-04-08 Switch to read confirmed_cases_table1_location_agg.csv
# ######################################################################

# ####
# VARS
# ####

use strict;
use autodie;

require 5.022; # lower would probably work, but has not been tested

# use Carp;
use Data::Dumper;
# print Dumper $data;
# use FindBin;
# use lib "$FindBin::Bin/libs";
# use Time::HiRes qw (sleep);
# alarm 10;

# No one should let me choose colours. Yet here we are
my %colours=(
    red=>"#ff0000",    # area of concern (was: western sydney)
    orange=>"#ff8800", # greater sydney and nearby
    purple=>"#990099", # regional lockdowns
    green=>"#cccc00",  # default
    default=>"#cccc00",# default
);

my $pp_num_days=365;
my $pp_oldest_day;
my $pp_box_size;
my $pp_vax_wide;

# ####
# SUBS
# ####

my @dates=();
my $from;
my $to;
my %lgas=();
my %postcodes=();
my %lockdowns=();
my $api_key;

# TODO - tally up the cases in each region, but only the recent ones
# my %gt_cases=(default=>0);

sub read_lockdowns($)
{
  my $file=shift;
  open(my $IN,$file) or die;
  my $url;
  my $colour;
  my $region;
  while(<$IN>){
    chomp;
    s/^\s*//;
    s/\s*$//;
    if(m/^#.*/ || m/^\s*$/){
      next;
    } elsif(m/^https?/){
      $url=$_;
    }elsif(m/^colour: (\S+)/){
      $colour=$colours{$1} or die "Internal error - '$1' is not an expected colour";
    }elsif(m/^region: (\S.*\S)/){
      $region=$1;
      # $gt_cases{$region}=0;
    } elsif(m/^[-a-z' ]+$/i){ # NOTE: we're assuming that Hunter's Hill will have an "'", if it ever appears. This may bite one day.
      my $lga=$&;
      $lockdowns{$lga}{colour}=$colour;
      $lockdowns{$lga}{region}=$region;
    } else {
      die "Didn't expect '$_' in lockdowns.txt";
    }
  }
}

sub read_vaccination($$)
{
  my $filename=shift or die;
  my $period=shift or die;
  open(my $IN,$filename) or die "Can't read '$filename': $!";
  my $extracted_at;
  while(<$IN>){
    if(m/Data extracted from AIR - as at 2359hrs on (.*)/){
      $extracted_at=$1;
      my $headers=<$IN>; 
      # We don't uses these, just want to skip the line, but also checking that it is as expected.
      # We've seen this change in harmless ways, so we could be more accepting. But would it be at the risk of not noticing a larger change?
      last if($headers=~m/LGA Name,Jurisdiction,Remoteness,Dose 1 % coverage of 15\+,Dose 2 % coverage of 15\+,Population aged 15\+/);
      last if($headers=~m/LGA 2019 Name of Residence,State of Residence,Remoteness,% Received dose 1 REMOTE_FLAGGED,% Received dose 2 REMOTE_FLAGGED,LGA Population/);
      last if($headers=~m/LGA 2019 Name of Residence,State of Residence,Remoteness,% Received dose 1 ?,% Received dose 2 ?,LGA Population/);
      last if($headers=~m/LGA 2019 Name of Residence\tState of Residence\tRemoteness\t% Received dose 1\s+% Received dose 2\s+LGA Population/);
      die "Failed to find headers in '$filename'";
    }
  }
  die unless $extracted_at;
  while(<$IN>){
    next if m/^,*$/;
    next if m/N\/A/i;
    next if m/Indicates LGAs with/;
    chomp;
    s/>95/95/g; # anything over 95 is rounded down to 95. Can be > 100 if area's population has grown since previous census, but can't be helped.
    my @fields=split /[\t,]/;
    #warn Dumper @fields;
    my $lga_name=$fields[0];
    my $dose1=$fields[3];
    my $dose2=$fields[4];
    my $population=$fields[5];
    $population.=$fields[6] if $fields[6];
    if(!$dose1){
      warn "No vax data: $_\n";
    }else{
      $dose1=~s/%//;
      $dose2=~s/%//;
    }
    $population=~s/\s*"\s*//g;
    $lga_name=clean_lga_name($lga_name);
    my $lga=$lgas{$lga_name} || next;
    $lga->{dose1}{$period}=$dose1;
    $lga->{dose2}{$period}=$dose2;
    $lga->{population}=$population; # Census data, won't change often
  }
}

sub read_api_key($)
{
  my $file=shift;
  open(my $IN,$file) or die;
  while(<$IN>){
    chomp;
    s/^\s*//;
    s/\s*$//;
    if(m/^#.*/ || m/^\s*$/){
      next;
    } elsif(m/^[-A-Z0-9_]{39}$/i){
      $api_key=$&;
      return 1;
    } else {
      die "Didn't expect '$_' in api key file '$file'";
    }
  }
  die "Didn't find an api key in aip key file '$file'";
}

sub clean_lga_name($) {
  my $lga_name=shift;
  $lga_name=~s/ \(.+\)//g;
  $lga_name=~s/ \(NSW\)//;
  return $lga_name;
}

sub read_cases($){
  my $file=shift;
  open(CSV,$file) or die;
  my $ignore_header=<CSV>;
  while(<CSV>){
    next if m/,,,,$/; # These seem to represent a non-disclosed case, e.g one in corrective services. Probably doesn't apply any more.
    chomp;
    # fields are: notification_date,postcode,lhd_2010_code,lhd_2010_name,lga_code19,lga_name19
    # notification_date,postcode,lhd_2010_code,lhd_2010_name,lga_code19,lga_name19,confirmed_by_pcr(always N/A?),confirmed_cases_count

    my @fields=split /,/;
    my $date=$fields[0];
    my $postcode=$fields[1];
    my $suburb=$fields[3];
    my $lga_name=$fields[5];
    my $case_count=$fields[7];
    if(!@dates || $date ne $dates[0]){
      unshift @dates, $date;
    }
    if(!$lga_name){
      if($suburb=~/Justice Health/){
      $lga_name='Correctional settings';
      $postcode='Correctional settings';
      }elsif($suburb=~/Hunter New England/){
        $lga_name='Upper Hunter';
        $postcode='2328'; # Whatever
      }else{
        warn "mystery suburb '$suburb' has no LGA";
        next;
      }
    }
    $lga_name=clean_lga_name($lga_name);
    $lgas{$lga_name}{cases}{$date}+=$case_count;
    $lgas{$lga_name}{postcodes}{$postcode}+=$case_count;
    # $suburbs{$suburb}{$date}+=$case_count;
    $postcodes{$postcode}{cases}{$date}+=$case_count;
    $postcodes{$postcode}{lgas}{$lga_name}=1;
  }
  # Pick the last however many full days, ignoring the latest day which is probably only a part day (TODO, print latest day, but with dashed lines?)
  @dates = reverse @dates[1..$pp_num_days];
  $from=$dates[0];
  $to=$dates[$#dates];
  die "expected > more data!\n" if !$to;
  return 1;
}

sub read_postcodes($){
  my $file=shift;
  open(CSV,$file) or die;
  binmode(CSV);
  while(<CSV>){
    next unless /NSW/;
    my @fields=split /,/;
    my $postcode=$fields[1];
    my $suburb=$fields[2];
    my $lat=$fields[14]; # Precise - to the suburb?
    my $lng=$fields[15];
    # my $lat=$fields[5]; # Approx - to the postcode?
    # my $lng=$fields[4];
    next if $suburb=~m/ DC$/; # Ignore? Or just strip the DC?
    if(!$lat || !$lng){
      warn "Skipping $postcode/$suburb\n";
      next;
    }
    $postcodes{$postcode}{lat}=sprintf("%.10g",$lat);
    $postcodes{$postcode}{lng}=sprintf("%.10g",$lng);
    $suburb=~s/([A-Z])([A-Z]+)/$1.lc($2)/ge;
    $postcodes{$postcode}{suburbs}{$suburb}=1;
  }
  $postcodes{'Correctional settings'}{lat}='-33.98968356474387';
  $postcodes{'Correctional settings'}{lng}='151.319736391778';
  return 1;
}

sub masked_postcode($)
{
  my $postcode_num=shift;
  return $postcode_num =~ m/Masked$|None$/ || !$postcode_num;
}

sub locate_lgas(){
  foreach my $lga_name (keys %lgas){
    my $lga=$lgas{$lga_name};
    my $lga_postcodes=$lga->{postcodes} or next;
    my $num_postcodes=%$lga_postcodes;
    my $avg_lat=0;
    my $avg_lng=0;
    foreach my $postcode_num (keys %$lga_postcodes){
      if(masked_postcode($postcode_num)){
        --$num_postcodes;
        next;
      }
      my $postcode=$postcodes{$postcode_num};
      if(!$postcode){
        warn "no postcode: $postcode_num\n";
        next;
      }
      if(!$postcode->{lat} || !$postcode->{lng}){
        warn "postcode $postcode_num has no lat (lga $lga_name)\n";
        next;
      }
      $avg_lat+=$postcode->{lat};
      $avg_lng+=$postcode->{lng};
    }
    if(!$num_postcodes){
      warn "LGA $lga_name has no unmasked postcodes\n";
      next;
    }
    $lgas{$lga_name}{lat}=sprintf("%.15g",$avg_lat/$num_postcodes);
    $lgas{$lga_name}{lng}=sprintf("%.15g",$avg_lng/$num_postcodes);
  }
  # Arbitrarily relocate 'Correctional Centre' to off Botany Bay.
  $lgas{'Correctional settings'}{lat}='-33.98968356474387';
  $lgas{'Correctional settings'}{lng}='151.319736391778';
  # Arbitrarily relocate 'Hotel quarantine' to offshore as well.
  $lgas{'Hotel Quarantine'}{lat}='-33.910105';
  $lgas{'Hotel Quarantine'}{lng}='151.319736391778';
}

sub print_header()
{
print qq[<!DOCTYPE html>
<html>
  <head>
    <title>NSW Covid Map</title>
    <meta name="viewport" content="initial-scale=1.0">
    <meta charset="utf-8">
    <style>
      html, body {
        height: 100%;
        margin: 0;
        padding: 0;
      }
      #map {
        height: 100%;
      }
    </style>
  </head>
  <body>
    <noscript>
      <P><font color="red">Sorry, but this page requires javascript.</font>
    </noscript>
    <div id="map"></div>
    <div id="legend"
         style="background: #fff;
           padding: 10px;
           margin: 10px;
           width: 100px;">
      <strong>Barcharts</strong>
      <BR>Vertical bars represents cases/day between $from and $to.
      <BR>Horizontal bars represents % of 1st & 2nd vaxed.
      <!-- <strong>Restrictions</strong> -->
      <!-- no one should have let me choose colours. Sorry. -->
      <div style="color: $colours{red}">Red: <A href="https://www.nsw.gov.au/covid-19/rules/affected-area">Area of Concern</A></div>
      <div style="color: $colours{orange}">Orange: <A href="https://www.nsw.gov.au/covid-19/rules/greater-sydney">Greater Sydney and nearby</A></div>
      <div style="color: $colours{purple}">Purple: <A href="https://www.nsw.gov.au/covid-19/rules/affected-regions">Newcastle and Hunter</A></div>
      <div style="color: $colours{green}">Green: <A href="https://www.nsw.gov.au/covid-19/rules/what-you-can-do-nsw">Other Rural and Regional</A></div>

      <BR><strong>Data from:</strong> <A href="https://data.nsw.gov.au/data/dataset/covid-19-cases-by-location/resource/21304414-1ff1-4243-a5d2-f52778048b29">data.nsw.gov.au</A>

      <!-- <BR>Hover the mouse over them for more detail.can comment this out for screenshots -->
      <!-- TODO Add buttons to choose between LGA and Postcodes -->
      <!-- TODO Move more of the locked down details into lockeddown.txt and read it from there -->
     <button id="toggle_display" onclick="toggle_display()">Toggle display</button> <!-- FIXME Smaller font please -->
      </div> <!-- end legend -->
    </div> <!-- end map -->
    <script type="text/javascript">
      var map;
      var displaying;
      var decorations=[]; <!-- FIXME this is just BFI - try to be smarter -->
      function init_map() {
        map = new google.maps.Map(
          document.getElementById("map"),
          {
            center: {
              // Fairfield
              // lat: -33.887203,
              // lng: 150.979458
              // Parramatta
              // lat: -33.7995485181818,
              // lng: 151.0328134909090
              lat: -33.887203,
              lng: 151.0328134909090
            },
            zoom: 11 // higher number = more zoomed in
          }
        );
        const legend = document.getElementById("legend");
        map.controls[google.maps.ControlPosition.RIGHT_BOTTOM].push(legend);
      };

      function add_box(n,w,s,e,c) {
        var box = new google.maps.Rectangle(
          {
            strokeColor: c,
            strokeOpacity: 0.8,
            strokeWeight: 2,
            fillColor: c,
            fillOpacity: 0.35,
            map: map,
            bounds: {
              north: n,
              west: w,
              south: s,
              east: e,
            }
          }
        );
        decorations.push(box);
        return box;
      }

      function add_circle(lat,lng,size,c) {
        var radius=50*Math.sqrt(size)
        var circle = new google.maps.Circle(
          {
            strokeColor: c,
            strokeOpacity: 0.8,
            strokeWeight: 2,
            fillColor: c,
            fillOpacity: 0.35,
            map: map,
            center: { lat: lat, lng: lng },
            radius: radius,
            // e.g. radius: Math.sqrt(citymap[city].population) * 100,
          }
        );
        decorations.push(circle);
      }

      function add_text(lat,lng,title,label,details) {
        const myLatLng = { lat: lat, lng: lng };
        const marker = new google.maps.Marker(
          {
            position: myLatLng,
            map: map,
            label: label,
            title: details,
            opacity: 0
          }
        );
//        const infowindow = new google.maps.InfoWindow({ content: details });
//        marker.addListener(
//          "mouseover", () => {
//            infowindow.open(
//              {
//                anchor: marker,
//                map,
//                shouldFocus: false,
//              }
//            );
//          }
//        );
//        marker.addListener(
//          "mouseout", () => {
//            infowindow.close();
//          }
//        );
        decorations.push(marker);
      }
      function add_boxes(name,label,text,lat,lng,cases,colour) {
        add_text(lat,lng,name,label,text);
        var high=$pp_box_size / 10;
        var wide=$pp_box_size; // For a single case to be a square, keep wide=high
        var s=lat;
        var w=lng;
        var first=1;
        // add_circle(s,w,10,colour);
        for (let day = 0; day < $pp_num_days; day++) {
          if(cases[day]>0){
            first=0;
            // n, w, s, e, colour
            add_box(s+cases[day]*high,w,s,w+wide,colour);
            // lat,lng,size
            // add_circle(s,w,cases[day],"#ff0000");
          }
          w+=wide;
        }
        if(first){
          add_circle(s,w,3,colour);
        }
        // No one should let me choose colours - help needed here please!
      }
      function undisplay_all_decorations(){
        // TODO: better to hide/unhide than delete/recreate
        // remove boxes and markers from map
        decorations.forEach(decoration => decoration.setMap(null));
        // delete all decorations
        decorations=[];
      }
      function toggle_display(){
        // FIXME This code almost but not quite works - it changes the cursor, but after the work is done (at least on firefox)
        // commenting it out for now
        // document.body.style.cursor = 'wait';
        // map.setOptions({draggableCursor:'wait'});
        undisplay_all_decorations()
        if(displaying == 'lgas'){
          // TODO: better to hide/unhide
          print_postcodes();
        }else{
          // TODO: better to hide/unhide
          print_lgas();
        }
        // document.body.style.cursor = '';
        // map.setOptions({draggableCursor:''});
      }
];
}

sub pick_colour(@)
{
  my @lga_names=@_;
  my $lockdown_details="";
  my $colour=$colours{default};
  # my $url=undef;
  foreach my $lga_name (@lga_names){
    $lga_name =~ s/^The //i;
    $lga_name =~ s/ Shire$//i;
    $lga_name =~ s/ Regional$//i;
    $lockdown_details=$lockdowns{$lga_name} or next;
    #$name .= " ($lockdown_details->{region})";
    $colour=$lockdown_details->{colour};
    last;
  }
  return qq{"$colour"};
}

sub print_cases($$$$$$@)
{
  my $name=shift;
  my $text=shift;
  my $cases=shift;
  my $population=shift;
  my $lat=shift or return; # FIXME "no lat for '$name'";
  my $lng=shift or die "no lng for '$name'";
  my @lga_names=@_;
  print "        // $name is at $lat,$lng\n";
  my $colour=pick_colour(@lga_names);
  print "        // $name is $colour hard locked down\n";
  print "        // $name cases: ";
  my $t_cases=0;
  # my @weekly_cases=();
  my $first;
  my $last;
  my $highest_cases=0;
  my $highest_msg="";
  foreach my $day (0 .. $pp_oldest_day) {
    my $date=$dates[$day];
    my $cases=$cases->{$date}||=0;
    $t_cases+=$cases;
    # $weekly_cases[$day<7 ? 0 : 1] += $cases;
    print " $cases";
    $first||=$date if $cases;
    $last=$date if $cases;
    if($cases>$highest_cases){
      $highest_cases = $cases;
      $highest_msg = "\\nPeak of ".case_s($cases)." on $date";
    }
  }
  # print ", total $t_cases ( $weekly_cases[0] : $weekly_cases[1])\n";
  print ", total $t_cases\n";
  #my $text="$name<p>";
  $text.="\\n";
  if(!$t_cases){
    $text .= "No recent cases";
  }else{
    print "        // $name: cases all fall between $first and $last\n";
    $text.=case_s($t_cases). ($first eq $last ? " on $first" : (" ".($t_cases==2? "on":"between"). " $first and $last"));
    $text.=sprintf(" (%.2f%% of population)",$t_cases/$population*100) if $population;
    $text.=$highest_msg if $highest_msg;
    # $text.="<p>";
    # foreach my $day (0..$pp_oldest_day) {
    #   my $date=$dates[$day];
    #   my $cases=$cases->{$date};
    #   next unless $cases;
    #   $text.="$date: $cases<br>";
    # }
    # if($weekly_cases[0]){
    #  my $r=$weekly_cases[1]/$weekly_cases[0];
    #  $text.=sprintf("<p>Week to week Reff=%0.2g",$r);
    # }
  }
  $name=~m/^[a-z0-9]/i or die;
  my $initial=$&;
  $name=~s/<br>/ /gi;
  print qq{        add_boxes("$name", "$initial", "$name\\n$text", $lat,$lng, [ };
  print join(", ",map {$cases->{$_}||0} @dates);
  print qq{ ], $colour);\n};
  print "\n";
}

sub print_hline($$$){
  my $lat=shift or return; # FIXME
  my $lng=shift or die;
  my $colour=shift or die;
  # my $high=$pp_box_size;
  my $wide=$pp_vax_wide;
  my $n=$lat; my $s=$lat; my $w=$lng; my $e=$w+$wide;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
}

sub print_vaxed($$$$$$$){
  my $lat=shift or die;
  my $lng=shift or die "No lattitude";
  my $dose1_cur=shift;
  my $dose2_cur=shift;
  my $dose1_prev=shift;
  my $dose2_prev=shift;
  my $colour=shift or die;
  my $high=$pp_box_size;
  if(!$dose1_prev || !$dose2_prev || $dose1_prev eq "N/A" || $dose2_prev eq "N/A"){
    print_hline($lat,$lng,$colour);
    return;
  }
  my $wide1c=$pp_vax_wide*$dose1_cur/100;
  my $wide2c=$pp_vax_wide*$dose2_cur/100;
  my $wide1p=$pp_vax_wide*$dose1_prev/100;
  my $wide2p=$pp_vax_wide*$dose2_prev/100;
  my $n=$lat-$high; my $s=$n-$high; my $w=$lng; my $e=$w+$wide1p;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  $e=$w+$wide1c;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  $n=$s;$s-=$high;$e=$w+$wide2p;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  $e=$w+$wide2c;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  # TODO: Wrap these in a function, for readability?
  $n=$n+$high;$e=$w+$pp_vax_wide;
  print qq{        var box=add_box($n,$w,$s,$e,$colour);\n};
  print qq{        box.fillOpacity=0;\n};
}

sub print_lgas(){
print qq[
      function print_lgas(){
];
  foreach my $lga_name (sort keys %lgas){
    my $lga=$lgas{$lga_name};
    my $lga_lat=$lga->{lat};
    my $lga_lng=$lga->{lng};
    my $title=$lga_name;
    $title.=" LGA" unless $lga_name =~ m/Correctional settings/;
    my $text="";
    if($lga->{population}){
      $text="Population $lga->{population}.";
      my $dose1=$lga->{dose1}{current};
      my $prev1=$lga->{dose1}{previous};
      if($dose1 && $dose1 ne "N/A" && $prev1){
        my $delta1=$dose1-$prev1;
        my $dose2=$lga->{dose2}{current};
        my $prev2=$lga->{dose2}{previous};
        my $delta2=$dose2-$prev2;
        $text .= sprintf " %0.1f%% 1st dosed and %0.1f%% double dosed, up %0.1f%% and %0.1f%% respectively on previous week.", $dose1, $dose2, $delta1, $delta2;
      }
    }
    print_cases(
      $title,
      $text,
      my $cases=$lga->{cases},
      $lga->{population},
      my $lat=$lga_lat,
      my $lng=$lga_lng,
      $lga_name,
    );
    # next if $lga_name =~ m/correctional settings/i;
#    print_vaxed(
#      $lga->{lat},
#      $lga->{lng},
#      $lga->{dose1}{current},
#      $lga->{dose2}{current},
#      $lga->{dose1}{previous},
#      $lga->{dose2}{previous},
#      my $colour=pick_colour($lga_name)
#    );
  }
print qq[        displaying = 'lgas';
      }
];
}

sub print_postcodes(){
print qq[
      function print_postcodes(){
];
  foreach my $postcode_number (sort keys %postcodes){
    next if masked_postcode($postcode_number); # Could guess based on LGA?
    my $postcode=$postcodes{$postcode_number}; # could be a Correction Centre
    my @lga_names=sort keys %{$postcode->{lgas}};
    my $num_lgas = @lga_names or next;
    #warn "postcode $postcode_number has multiple LGA: @lga_names\n" if $num_lgas!=1;
    my @suburbs=sort keys %{$postcode->{suburbs}};
    my $suburbs=join ", ", @suburbs;
    my $lga_names=join "/", @lga_names;
    print_cases(
      my $title="Postcode $postcode_number",
      my $text="$suburbs.\\n$lga_names LGA",
      my $cases=$postcode->{cases},
      undef, # population, which we don't have
      my $lat=$postcode->{lat},
      my $lng=$postcode->{lng},
      @lga_names
    );
    my $colour=pick_colour(@lga_names);
    print_hline($lat,$lng,$colour);
  }
print qq[        displaying = 'postcodes';
      }
];
}

sub print_tail(){
print qq[
      function init(){
        init_map();
        print_lgas();
      }
    </script>
    <script src="https://maps.googleapis.com/maps/api/js?key=$api_key&libraries=drawing&callback=init" async defer></script>

  </body>
</html>
];
}

sub case_s($)
{
  my $cases=shift;
  return "$cases case".($cases==1?"":"s");
}

# ####
# MAIN
# ####

# Files

my $case_file='confirmed_cases_table1_location_agg.csv';
my $postcode_file='australian_postcodes.csv';
my $lockdown_file='lockdowns.txt';
my $current_vaccination_file='covid-19-vaccination-local-government-area-lga-6-december-2021.csv';
my $previous_vaccination_file='covid-19-vaccination-local-government-area-lga-13-december-2021.csv';
my $api_key_file='google_maps_api_key.txt';
my $local_api_key_file='local_google_maps_api_key.txt';

my $out_file="map/index.html";
my $local_out_file="local_nsw_covid_map.html";

while (my $argv = shift @ARGV) {
  if($argv eq '-l'){
    $out_file=$local_out_file;
    $api_key_file=$local_api_key_file;
  }elsif($argv eq '-d'){
    $pp_num_days=shift or die $usage;
  }else{
    die $usage;
  }
}

$pp_oldest_day=$pp_num_days-1;
$pp_box_size=0.002*14/$pp_num_days;
$pp_vax_wide=0.002*14;

read_cases($case_file) or die;
read_postcodes($postcode_file) or die;
locate_lgas();
read_lockdowns($lockdown_file);
read_vaccination($current_vaccination_file,'current');
read_vaccination($previous_vaccination_file,'previous');
read_api_key($api_key_file);

open(my $OUT,">",$out_file) or die "Can't write '$out_file': $!\n";
binmode($OUT);
select $OUT;

print_header();

print STDOUT "Printing LGAs.\n";
print_lgas();
print STDOUT "Printing postcodes.\n";
print_postcodes();

print_tail();

select STDOUT;

print "Created $out_file\n";
print "Done\n";