@rem This assumes you have a wget.exe, or equivalent.
@rem TODO: work out how to do the same thing using Invoke-WebRequest
wget.exe --no-check-certificate https://data.nsw.gov.au/data/dataset/aefcde60-3b0c-4bc0-9af1-6fe652944ec2/resource/21304414-1ff1-4243-a5d2-f52778048b29/download/confirmed_cases_table1_location.csv
dir confirmed_cases_table1_location.csv*
