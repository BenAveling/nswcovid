# This assumes you have a wget.exe, or equivalent.
# TODO? work out how to do the same thing using Invoke-WebRequest?
git pull
# not sure why this doesn't work - used to. no longer does
# wget.exe --no-check-certificate https://data.nsw.gov.au/data/dataset/aefcde60-3b0c-4bc0-9af1-6fe652944ec2/resource/21304414-1ff1-4243-a5d2-f52778048b29/download/confirmed_cases_table1_location.csv
# this is no longer updated:
# wget https://data.nsw.gov.au/data/dataset/aefcde60-3b0c-4bc0-9af1-6fe652944ec2/resource/21304414-1ff1-4243-a5d2-f52778048b29/download/confirmed_cases_table1_location.csv -outfile confirmed_cases_table1_location.1.csv
# this seems to work.
wget https://data.nsw.gov.au/data/dataset/aefcde60-3b0c-4bc0-9af1-6fe652944ec2/resource/5d63b527-e2b8-4c42-ad6f-677f14433520/download/confirmed_cases_table1_location_agg.csv -outfile confirmed_cases_table1_location_agg.csv
# No longer necessary, data now comes sorted
# perl sort_cases.pl confirmed_cases_table1_location.1.csv confirmed_cases_table1_location.csv
