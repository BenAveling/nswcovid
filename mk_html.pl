#!/usr/bin/perl -w

# ######################################################################

#   Copyright (C) 2021  Ben Aveling

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
# FIXME: One of our 'LGAs' is the collective correctional system.
# This possibly breaks multiple unconscious assumptions.
# But (except briefly), the cases in Justice Health don't have an LGA
# e.g. 2020-07-29,,,Justice Health,,
# One option might be to put Justice Health at
# -33.98968356474387, 151.319736391778 (i.e. Botany Bay)
# ######################################################################

my $usage = qq{Usage:
  perl mk_html.pl [-l] [-d num_days]

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
    yellow=>"#aaaa00", # hunter (so far)
    purple=>"#990099", # default
);

my $pp_num_days=90;
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

sub read_vaccination($)
{
  my $vaccination_file=shift or die;
  open(my $IN,$vaccination_file) or die;
  my $extracted_at;
  while(<$IN>){
    if(m/Data extracted from AIR - as at 2359hrs on (.*),,,,,/){
      $extracted_at=$1;
    }
    last if(m/LGA Name,Jurisdiction,Remoteness,Dose 1 % coverage of 15\+,Dose 2 % coverage of 15\+,Population aged 15\+/);
  }
  die unless $extracted_at;
  while(<$IN>){
    chomp;
    my @fields=split /,/;
    #warn Dumper @fields;
    my $lga_name=$fields[0];
    my $dose1=$fields[3];
    my $dose2=$fields[4];
    my $population=$fields[5];
    $population.=$fields[6] if $fields[6];
    $population=~s/"//g;
    $lga_name=clean_lga_name($lga_name);
    my $lga=$lgas{$lga_name} || next;
    $lga->{dose1}=$dose1;
    $lga->{dose2}=$dose2;
    $lga->{population}=$population;
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
    next if m/,,,,$/; # These seem to represent a non-disclosed case, e.g one in corrective services
    chomp;
    # fields are: notification_date,postcode,lhd_2010_code,lhd_2010_name,lga_code19,lga_name19
    my @fields=split /,/;
    my $date=$fields[0];
    my $postcode=$fields[1];
    my $suburb=$fields[3];
    my $lga_name=$fields[5];
    if(!@dates || $date ne $dates[0]){
      unshift @dates, $date;
    }
    if(!$lga_name){
      die unless $suburb=~/Justice Health/;
      $lga_name='Correctional settings';
      $postcode='Correctional settings';
    }
    $lga_name=clean_lga_name($lga_name);
    $lgas{$lga_name}{cases}{$date}++;
    $lgas{$lga_name}{postcodes}{$postcode}++;
    # $suburbs{$suburb}{$date}++;
    $postcodes{$postcode}{cases}{$date}++;
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

sub locate_lgas(){
  foreach my $lga_name (keys %lgas){
    my $lga=$lgas{$lga_name};
    my $lga_postcodes=$lga->{postcodes} or next;
    my $num_postcodes=%$lga_postcodes;
    my $avg_lat=0;
    my $avg_lng=0;
    foreach my $postcode_num (keys %$lga_postcodes){
      if($postcode_num eq 'Masked' || !$postcode_num){
        --$num_postcodes;
        next;
      }
      my $postcode=$postcodes{$postcode_num} or warn "no postcode: $postcode_num";
      die "postcode $postcode_num has no lat" if ! $postcode->{lat};
      $avg_lat+=$postcode->{lat};
      $avg_lng+=$postcode->{lng};
    }
    $lgas{$lga_name}{lat}=sprintf("%.15g",$avg_lat/$num_postcodes);
    $lgas{$lga_name}{lng}=sprintf("%.15g",$avg_lng/$num_postcodes);
  }
  # Arbitrarily relocate 'Correctional Centre' to off Botany Bay.
  $lgas{'Correctional settings'}{lat}='-33.98968356474387';
  $lgas{'Correctional settings'}{lng}='151.319736391778';
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
      <div style="color: $colours{yellow}">Yellow: <A href="https://www.nsw.gov.au/covid-19/rules/affected-regions">Newcastle and Hunter</A></div>
      <div style="color: $colours{purple}">Purple: <A href="https://www.nsw.gov.au/covid-19/rules/what-you-can-do-nsw">Other Rural and Regional</A></div>

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
        var high=$pp_box_size;
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
  my $colour=$colours{purple};
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

sub print_cases($$$$$@)
{
  my $name=shift;
  my $text=shift;
  my $cases=shift;
  my $lat=shift or die "no lat for '$name'";
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
  foreach my $day (0 .. $pp_oldest_day) {
    my $date=$dates[$day];
    my $cases=$cases->{$date}||=0;
    $t_cases+=$cases;
    # $weekly_cases[$day<7 ? 0 : 1] += $cases;
    print " $cases";
    $first||=$date if $cases;
    $last=$date if $cases;
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
  my $lat=shift or die;
  my $lng=shift or die;
  my $colour=shift or die;
  my $high=$pp_box_size;
  my $wide=$pp_vax_wide;
  my $n=$lat; my $s=$lat; my $w=$lng; my $e=$w+$wide;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
}

sub print_vaxed($$$$$){
  my $dose1=shift or die;
  my $dose2=shift or die;
  my $lat=shift or die;
  my $lng=shift or die;
  my $colour=shift or die;
  my $high=$pp_box_size;
  if($dose1 eq "N/A" || $dose2 eq "N/A"){
    print_hline($lat,$lng,$colour);
    return;
  }
  $dose1=~s/%//;
  $dose2=~s/%//;
  my $wide1=$pp_vax_wide*$dose1/100;
  my $wide2=$pp_vax_wide*$dose2/100;
  my $n=$lat; my $s=$n-$high; my $w=$lng; my $e=$w+$wide1;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  $n=$s;$s-=$high;$e=$w+$wide2;
  print qq{        add_box($n,$w,$s,$e,$colour);\n};
  # TODO: Wrap these in a function, for readability?
  $n=$lat;$s=$n-2*$high;$w=$lng;$e=$w+$pp_vax_wide;
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
    my $text=$lga->{population} ? "Population $lga->{population}, $lga->{dose1} 1st dosed and $lga->{dose2} double dosed" : "";
    warn "bad lga: $lga_name" if $text =~ /  /;
    print_cases(
      $title,
      $text,
      my $cases=$lga->{cases},
      my $lat=$lga_lat,
      my $lng=$lga_lng,
      $lga_name,
    );
    next if $lga_name =~ m/correctional settings/i;
    print_vaxed(
      $lga->{dose1},
      $lga->{dose2},
      $lga->{lat},
      $lga->{lng},
      my $colour=pick_colour($lga_name)
    );
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
    next if !$postcode_number || $postcode_number eq "Masked"; # Could guess based on LGA...
    my $postcode=$postcodes{$postcode_number}; # could be a Correction Centre
    my @lga_names=sort keys %{$postcode->{lgas}};
    my $num_lgas = @lga_names or next;
    warn "postcode $postcode_number has multiple LGA: @lga_names\n" if $num_lgas!=1;
    my @suburbs=sort keys %{$postcode->{suburbs}};
    my $suburbs=join ", ", @suburbs;
    my $lga_names=join "/", @lga_names;
    print_cases(
      my $title="Postcode $postcode_number",
      my $text="$suburbs.\\n$lga_names LGA",
      my $cases=$postcode->{cases},
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

my $case_file='confirmed_cases_table1_location.csv';
my $postcode_file='australian_postcodes.csv';
my $lockdown_file='lockdowns.txt';
my $vaccination_file='covid-19-vaccination-geographic-vaccination-rates-local-government-area-lga.csv';
my $api_key_file='google_maps_api_key.txt';
my $local_api_key_file='local_google_maps_api_key.txt';

my $out_file="nsw_covid_map.html";
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
read_vaccination($vaccination_file);
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
