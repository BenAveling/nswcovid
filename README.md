# nswcovid

An interactive map of NSW showing selected publicly available Covid data:

<http://benaveling.github.io/nswcovid/map/>

Each little barchart represents cases/day for a geographic area over the last 90 days of available data (configurable).

Case data is from [data.gov.au](https://data.nsw.gov.au/data/dataset/covid-19-cases-by-location/resource/21304414-1ff1-4243-a5d2-f52778048b29)

Vaccination data is from: https://www.health.gov.au/resources/collections/covid-19-vaccination-geographic-vaccination-rates-lga

Case data will always be at least two days out of date.

Upstream data is never quite up to date and is often revised after being published - cases are added and removed and moved to different days or different areas. 

This is especially true for the last day of data - it's often around half the actual cases.  And therefore, the most recent day of data isn't displayed - it would be misleading to do so.

Vaccination data is only released once a week, it will always be one to weeks out of date.

This project is shared in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

History

2021-08-05 An initial upload, consider it a working proof of concept
2021-09-19 Lots of little changes, including vaccination data, displaying by lga or by suburb, some changes into input data and other small stuff.
