To regenerate the map:

Download latest data

  wget.bat 

Create a local version (assumes you have a valid api key; if not, see below)

  perl mk_html.pl -l

Open in browser

  start .\local_nsw_covid_map.html

To create a version that can be uploaded to github

  perl mk_html.pl

If you want to compare first:

  vim -d nsw_covid_map.html map/index.html

When ready to upload

  git add .
  git commit -m "update data to <date>"
  git push

You can get a new google api key from:

  https://developers.google.com/maps/documentation/places/web-service/get-api-key

More than a certain number of requests a month starts to cost money. It's a fairly large number, perhaps 28,000?
