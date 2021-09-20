To regenerate the map:

  perl mk_html.pl

By default, a github specific google-maps key is used.

To create a version that can be used on your PC, you need a valid api key (see below)

Then:

  perl mk_html.pl -l

To download the latest data

  wget.bat 

And then rename or copy to:

  confirmed_cases_table1_location.csv

To download vaccination data, you need to convert from .xlsx to .csv, and update the hardcoded filenames in mk_html.pl

e.g.

  my $current_vaccination_file='covid-19-vaccination-by-lga.2021-09-13.csv';
  my $previous_vaccination_file='covid-19-vaccination-by-lga.2021-09-06.csv';

To open in browser:

  start .\local_nsw_covid_map.html

To create a version that can be uploaded to github

  perl mk_html.pl

If you want to compare first:

  vim -d nsw_covid_map.html map/index.html

When ready to upload

  git add .
  git commit -m "update data to <date>"
  git push

Wait a minute, then sanity check at

  https://benaveling.github.io/nswcovid/map/

Look for the date to be updated.

== Google API Key ==

To open a map on your own PC, or to host on your own website, you need a google api key, which you can get from:

  https://developers.google.com/maps/documentation/places/web-service/get-api-key

More than a certain number of requests a month starts to cost money. It's a fairly large number of requests, perhaps 28,000?

To monitor, visit the console:

  https://console.cloud.google.com/
