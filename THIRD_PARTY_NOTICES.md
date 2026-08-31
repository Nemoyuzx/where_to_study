# Third-Party Notices

## UAPI weather and lunar-calendar service

Where To Study uses the public HTTPS APIs documented by [UAPI](https://uapis.cn/docs/) to display
campus-district weather and selected-date lunar-calendar information. UAPI is an external data service;
no UAPI source code or data file is redistributed with this project. Availability and returned data are
subject to the service provider's terms and policies.

## Timeless almanac advice service

Where To Study may use the public HTTPS API documented by
[Timeless API](https://api.timelessq.com/docs/api-15277838) to supplement the selected date's
`宜` and `忌` text. Timeless is an external data service; no Timeless source code or data file is
redistributed with this project. If the service is unavailable, the app retains the base lunar-calendar
information returned by UAPI.

## Contest DDL public event data

Where To Study reads public competition, academic-conference, journal-special-issue, summer-camp,
pre-admission, and hackathon deadline data from
[Contest DDL](https://nemoyuzx.github.io/contest-ddl/) and may use its fixed backup API when the
primary endpoint is unavailable. These are external data services; no service source code or complete
event dataset is redistributed with the application. Every corresponding card identifies the external
source, and users can disable each event category separately.

The same card also reads public BUPT competition notices and their extracted deadline nodes from the
fixed [`contest-notices` API](https://where-to-study.cn/api/contest-notices). Each item links back to the
corresponding HTTPS notice page on `ucloud.bupt.edu.cn`. The API is an external read-only data service;
its source code and complete dataset are not redistributed with the application.

## BUPT campus shuttle notices

Where To Study reads structured campus-shuttle information from the fixed
[`shuttle-bus` API](https://where-to-study.cn/api/shuttle-bus). The service derives its notices,
departure locations, and official timetable images from public pages published by the
[BUPT Logistics Department](https://hq.bupt.edu.cn/tzgg.htm). Table recognition is automated and
strictly validated before a structured schedule is exposed; the application does not redistribute a
complete archive and always links back to the official notice. Shuttle times are for reference only,
especially on statutory holidays or after temporary operating changes.

## Beijing University of Posts and Telecommunications UCloud

The teaching-calendar assignment card links to the university's official
[UCloud assignment page](https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3)
and reads its assignment response format after the user has saved valid BUPT credentials. Authentication
is performed natively through the university's HTTPS CAS service; the app does not redistribute UCloud
code or read browser sessions. UCloud and the BUPT authentication service are external university
services and may process ordinary network metadata under their own policies.

## holiday-calendar

Where To Study retrieves Chinese public-holiday and transfer-workday data from
[`cg-zhou/holiday-calendar`](https://github.com/cg-zhou/holiday-calendar). The upstream project states
that its Chinese data is compiled from annual holiday-arrangement notices issued by the General Office
of the State Council. The dataset and accompanying software are provided under the following license.

MIT License

Copyright (c) 2025 holiday-calendar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
