Sender : ObjectiveFS <info@objectivefs.com> 

Date : 2025-12-08 08:42 (GMT+9)

Title : Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

To : 이주평<jupyung.lee>

Hi Jupyung,



Thank you for your email. We understand the urgency of this issue.



To help us provide the best suggestion to solve the performance degradation issue, please confirm the following:



1. What is the filesystem size (df -h) and number of objects?

- Earlier Yeo-jun from Samsung mentioned it was a 21GB filesystem with 80K objects, but in your email there are 10 million objects. The immediate remedy to address an 80K vs 10 million objects filesystem will be different and we appreciate if you could provide the information to us.

2. If possible, please provide the objectivefs log file on the system seeing the issue, so our engineers can see there is anything unusual about the filesystem requests. The reason we ask is because we have customers running on Ceph and do not see this issue on their clusters. 



I believe the issue is likely due to the number of objects, if there are 10 million objects on your filesystem. Disabling the automatic snapshots is unlikely going to address the issue, since the number of requests from snapshots is quite small compared to the regular requests, especially if the caches are not large enough to hold the frequently used metadata and data.



Here are a few suggestions that can help reduce the amount of requests to the object store:

1. Increase the memory cache size

- A larger memory cache can reduce the number of requests to the bucket.

- The memory cache size can be set using /etc/objectivefs.env/CACHESIZE and will take effect upon remount.

- I think Yeo-jun mentioned that it is currently not set, therefore using the default 20% of server RAM. I suggest increasing the CACHESIZE to for example 50% to begin with.



2. Enable disk cache and use a disk cache size that is large enough to hold the frequently used data.



3. Verify that this Ceph bucket has the “delete-object” operation enabled, so objects can be deleted.



4. If the storage layout is not optimized, there will be lots of requests to the object store. The solution is to run high compaction for a few days to optimize the storage layout. This will increase the amount of requests to the bucket in the short term, but will help reduce the number of requests afterwards. An optimized storage layout will have better memory utilization, faster performance and fewer requests to the object store (for a 10 million object filesystem, an optimized storage could have 10x less requests). I suggest running high compaction at your earliest convenience for a good long term solution.



If you have any questions, please feel free to contact us.



Sincerely,

Steve



> On Dec 7, 2025, at 8:49 AM, 이주평 <jupyung.lee@samsung.com> wrote:

>

> Hi Steve,

>

> Thanks for your response. The situation is very urgent as the incident has occurred once again right now, impacting our critical service.

> I am writing this hoping that you can reply back to us ASAP.

> This service utilizes ObjectiveFS to mount a ceph bucket containing over 10 million objects. At times (including right now), mounting this bucket using ObjectiveFS significantly degrades the overall Ceph cluster performance.

> Unmounting the bucket leads to performance recovery, but remounting it again results in performance degradation again.

> What ObjectiveFS options should we consider adjusting to prevent this performance degradation caused by the mount? We are considering disabling snapshot using 'mount.objectivefs snapshot -s "" <filesystem>'. Do you have any other suggestions?

>

> Your prompt response will be greatly appreciated.

>

> Best,

>

> Jupyung (JP) Lee, PhD  |  Corporate Vice President

> Cloud Architecture Team Lead  |  Samsung SDS

>

> --------- Original Message ---------

> Sender : ObjectiveFS <info@objectivefs.com>

> Date  : 2025-12-06 14:05 (GMT+9)

> Title : Re: Issues Using ObjectiveFS on SamsungSDS Cloud

>

> Hi Yujin,

>

> Thank you for your email. I have included the answers to your questions below (inline with the questions). Our engineers are also happy to have a call to provide additional details and answer any additional questions that you have.

> If you are interested in having a call, please let me know and I am happy to provide some suggested times for the call.

>

> Sincerely,

> Steve

>

> > > While utilizing ObjectiveFS on the SamsungSDS Cloud Platform (SCP), a Hang error occurred in Ceph, which serves as the Object Storage in SCP.

> > Regarding this issue, please refer to the inquiry below for further details.

> > > 1. Get Object operation

> > - Whether get-object is used for purposes other than object downloading.

>

> Answer: Yes, the Get request is also used by the compaction process that optimizes the storage layout.

>

> > - A large number of get-object requests for non-existent objects occur periodically, resulting in a 404 error. What is the purpose of this logic?

> > This logic occurs periodically and places a large load on Ceph. Please refer to the picture below.

>

> Answer: This is done to verify that response from the object store for list request is up-to-date and correct. This is important particularly for object stores with List operations that are eventually consistent or are slow to update, to ensure ObjectiveFS has a correct view of the data in the object store.

>

> > - Can this get-object be replaced with head-object?

>

> Answer: It might be possible, but would require engineering effort to determine the effects of the change on the compaction process.

>

> > <Mail Attachment.jpeg>

> > 2. list object operation

> > - The graph below shows a hang error that occurred at the specified time.

> >  At 12:10, the application load was halted. However, we observed that List & Delete Object requests were still being issued, even though ObjectiveFS was only mounted.

> >  Internally, Ceph became locked while processing these List & Delete requests, preventing any other requests from being processed during that period.

> >  Is it normal for a List Object request to be issued when ObjectiveFS is mounted? If so, what is its specific purpose?

>

> Answer: Yes, List and Delete requests are also issued for compaction, snapshots, etc.

>

> > - Whether retry logic exists for list-objects and get-object failures ?

>

> Answer: Yes, ObjectiveFS will always retry failed requests.

>

> > - what are the retry settings (wait time/number of attempts)?

> Answer: ObjectiveFS follows AWS best practice for retry such as using exponential backoff for retries.

>

> > - Processing when list-object responses take a long time.<Mail Attachment.jpeg>

> Answer: ObjectiveFS processing when encountering a slow List request depends on the reason for issuing the List request. For example, if the List was issued because of compaction, there should be no impact. If the List request was issued because of filesystem activity, the processing could be blocked if the response is needed for filesystem correctness.

>

> > 3. Basic Operations during Mount

> > - Whether to perform list-objects every two minutes while in Mount state. How to change the frequency or disable it.

>

> Answer: Currently, the frequency for List requests cannot be changed or disabled.

>

> > - Mount/Unmount Process.

> Answer: The mount process uses List to enumerate the objects in the bucket. Using the object cache (mount option: ocache (enabled by default)) can reduce the number of List requests during mount time.

>

> The unmount process will finish any in-progress operations before exiting.

>

> > - Periodic routine for object storage while maintaining the Mount state.

>

> Answer: There is a compaction process that runs in the background to optimize the storage layout, by bringing together related data from different objects. Also, depending on the activity on the filesystem, there might also be some periodic operations required to maintain POSIX compatibility.

> > - Minimum TPS required / Maximum TPS possible while in Mount state.

>

> Answer: The amount of TPS depends on the filesystem size, activity and workload. For a large filesystem with a lot of activity, the number of requests per second could be in the range of thousands. ObjectiveFS is designed to scale with the object store performance, from small filesystems on small object stores to large filesystems on larger object stores. For example, AWS S3 supports up to 3,500 PUT/POST/DELETE and 5,500 GET transactions per second (TPS) per partitioned prefix.

> > 4. File Read/Write

> > - Calls to Object Storage during File Reads

> > . One get-object call per read / A combination of more than one call, such as performing a get-object after a head-object check.

>

> Answer: For reads, ObjectiveFS only needs to fetch the part of the file that is read. For example, if only 100KB of a 2GB file is read, only that 100KB is fetched. Get requests are sent for that part of the file. For large reads, ObjectiveFS can send multiple Get requests in parallel to increase performance.

>

>

> > - Calls to Object Storage during File Writes

> > . One put-object call per write / A combination of more than one call, such as verifying the object with head-object, completing put-object, and then checking the result again with get-object or head-object.

>

> Answer: For writes, Put requests are sent as the data is written. Many writes close in time can be combined into a single Put requests. For example, if unzipping a directory with many small files, they might all be written as a single Put request.

>

>

> > 5. Cache Operation

> > - Existence of a cache.

>

> Answer: Yes, ObjectiveFS has many levels of caches: memory cache, disk cache, kernel cache and object store cache,

> > - Cache operation process.

>

> Answer: The memory cache is filled on file reads and writes. The disk cache is filled on file reads. The kernel cache is filled on file read. The object store cache is updated as needed.

>

> > - Periodic routines occurring during cache operation.

>

> Answer: Disk cache is checked to make sure it is kept within the disk cache setting limit, and will evict data to keep the disk cache space within the limit.

> > - How to change cache settings.

>

> Answer: The memory cache size can be changed using the environment variable CACHESIZE. The disk cache size can be changed using the environment variable DISKCACHE_SIZE. The kernel cache is enabled when multithreading is enabled on Team plan or higher. The object store can be enabled using the “ocache” mount option (on by default).

> > - The possibility of a get-object request for a deleted object during cache operation.

> Answer: Yes, this is possible since a list operation is not called before each Get request. So, an object could be deleted by another node right before the Get request is sent.

>

> > > The situation is urgent, so we kindly request a prompt response.

> > Thank you,
> > Kang, Yujin

> > SCP Compute Architecture Group / Group Leader

> > M +82-10-6799-6748

> > E yj6.kang@samsung.com<Mail Attachment.jpeg>

> > --------- Original Message ---------

> > Sender : 박성일 <s-park.park@samsung.com>/Drive개발그룹(IW개발)/삼성SDS

> > Date : 2025-11-28 11:48 (GMT+9)

> > Title : (Objectivefs컨택포인트)FW: FW: Re: [Tangunsoft] Inquiry Regarding License Usage and Instance Counting for SamsungSDS - ObjectiveFS

> > > 본 메일은 저희가 최근 며칠간 Objectivefs 측과 문의 및 답변받은 내용들을 참고차 보내드립니다.

> > > -------------------

> > > 저희는 공급사 통해서 연락하거나, 급할때는 objectivefs에 직접 메일로 연락하기도 합니다.

> > 본사는 미국 노스캐롤라이나로 추정됩니다.

> > > - 단군 소프트/김여중<yjkim@tangunsoft.com>/010-2407-6206

> > - objectivefs/support@objectivefs.com

> > > 아래는 제가 공홈에서 찾아본 전화번호입니다.

> > > Contact Us

> > Email: info@objectivefs.com

> > Phone: +1-415-997-9967

> > Location:

> > 4801 Glenwood Ave Ste 200

> > Raleigh, NC 27612

> > U.S.A.

> > > --------- Original Message --------- > Sender : ObjectiveFS <support@objectivefs.com> > Date : 2025-11-27 23:18 (GMT+9) > Title : Re: [Tangunsoft] Inquiry Regarding License Usage and Instance Counting for SamsungSDS - ObjectiveFS > To : 김여중<yjkim@tangunsoft.com>

> > > Hi Yeo-jung,

> > > Thank you for the information. Based on the information provided, our engineers believe the cause of these issues are because requests did not succeed and have to be retried. The requests timeouts are in the 10 seconds range, matching the slow file creation that the customer saw.

> > > I have included some items to check, diagnostic steps and answers to the customer’s questions below.

> > > A. Items to Check

> > -----------------

> > ObjectiveFS can open many parallel connections to the object store. ObjectiveFS uses connection pooling and connections are reused. Here are a couple of items to check to make sure the requests succeed quickly:

> > 1. Check that the object store is configured to handle hundreds of parallel requests 2. Check that the proxy and/or firewall between the server and object store (if any) are not limiting the connections to the object store.

> > > B. Diagnostic steps -------------------

> > Please request the customer to run the following steps to help us diagnose this issue:

> > 1. Unmount and remount the filesystem on “/ofs"

> > - If possible, please provide the starting line of the objecivefs mount from the log.

> > > 2. Run a single “ls /ofs” on the mount. - Question: Do you see any retry messages in the log?

> > > 3. Run "find /ofs”

> > - Question: Do you see any retry messages in the log?

> > > 4. Run “touch /ofs/test.txt”

> > - Question: Do you see any retry messages in the log?

> > > > C. Answers to the customer’s questions

> > ---------------------------------------

> > > > Is there a way to check the queues that Objectivesfs sends to AWS S3 or other objectstore?

> > > > Yes, by checking the number of open connections to the object store endpoint using for example “netstat”.

> > > > And I want to know what the retry logic is for requests or connections. If we put the load in, the retry log keeps happening, but I want to check it because it feels overlapping.

> > > > A request is retried if the object store didn’t return a successful/valid response. Unsuccessful requests are then retried based on an exponential backoff schedule. Sincerely,

> > Steve

> > > > On Nov 27, 2025, at 4:04 AM, 김여중 <yjkim@tangunsoft.com> wrote:

> > > > Hello Team,

> > > I'm Yeo-jung from Tangunsoft.

> > > > I was contacted very urgently by the client.

> > > I would appreciate it if you could quickly check and reply to the previous inquiries and inquiries below.

> > > ==

> > > Is there a way to check the queues that Objectivesfs sends to AWS S3 or other objectstore?

> > > > And I want to know what the retry logic is for requests or connections. If we put the load in, the retry log keeps happening, but I want to check it because it feels overlapping.

> > > ==

> > >  > Thank you & Best Regards,

> > > Yeo-jung Kim
> > > > -----Original Message-----

> > > From: 김재희 <jay@tangunsoft.com> > Sent: Thursday, November 27, 2025 3:37 PM

> > > To: ObjectiveFS <support@objectivefs.com>

> > > Cc: CS <cs@tangunsoft.com>

> > > Subject: RE: [Tangunsoft] Inquiry Regarding License Usage and Instance Counting for SamsungSDS - ObjectiveFS > > Hi, Sam

> > > > I wrote about the items they can answer.

> > > > > 1. What type of object store is the customer using (e.g. AWS govcloud, Azure, on-premise, etc)?

> > > Other S3-compatible object stores

> > > > > 2. Is the server mounting the filesystem in the same region as the object store?

> > > Yes, they are in the same region.

> > > > > 3. What is the latency from the server to the object store? If possible, please provide provide the ping time from the server to the object store (by running "ping <object store endpoint>" from the server).

> > > HTTP/1.1 200 OK

> > > date: Wed, 26 Nov 2025 10:16:58 GMT

> > > content-type: application/xml

> > > transfer-encoding: chunked

> > > > > [225 bytes data]

> > > 214 .....

> > > Connection #0 to host object-store.private.kr-south2.g.samsungsdscloud.com left intact <? xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="https://protect2.fireeye.com/v1/url?k=54bb6736-3530720f-54baec79-000babffae10-2279d5d767be9913&q=1&e=b63ae42f-606a-437e-a926-d47a2107ff19&u=http%3A%2F%2Fs3.amazonaws.com%2F

> > > BucketsResult>DNS:0.000777s TCP:0.001403s TTFB:0.004475s Total:0.004594s

> > > > > 4. What is the performance of the object store (if possible to provide):

> > > a) approximate latency for PUT requests

> > > b) approximate latency for GET requests

> > > c) approximate latency for LIST requests [Attach a Picture]

> > > > > > 5. Are there are firewall/proxy/scanner between the server and the object store?

> > > > > 6. How much RAM is on the server?

> > > 64GB

> > > > > 7. What is the memory cache size (usually specified in /etc/objectivefs.env/CACHESIZE) [if set]?

> > > Don't set it up separately

> > > Default

> > > > > 8. Is TLS enabled (i.e. is the endpoint specified with "https://" or /etc/objectivefs.env/TLS set to 1)?

> > > Using TLS

> > > > > 9. Is this filesystem mounted on one server or multiple servers?

> > > a) If multiple servers, is the file creation done from one server or multiple servers?

> > > multiple servers, multiple creation

> > > > > 10. Can you provide the following information for this filesystem:

> > > a) Size of the filesystem: Output in the "Size" column of "df -h"

> > > Total 1EB Use 21G

> > > > > b) Number of objects in the bucket: Output of the "IUsed" column of "df -i"

> > > About 80,000 of them

> > > > > 11. Version of ObjectiveFS

> > > 7.2.1

> > > > > 12. Which ObjectiveFS license is the customer using? They currently have two licenses: one Enterprise and one Corporate.

> > > Enterprise

> > > > > > > Best regard,

> > > > > > Tangunsoft Co., Ltd. / Customer Innovation Team / Manager Jay Kim Direct 82.2.6206.2542 / Mobile 010.3967.6206 / Fax 82.2.538.1153 E-mail jay@tangunsoft.com / Web https://protect2.fireeye.com/v1/url?k=893581d9-e8be94e0-89340a96-000babffae10-2093443f540fcd80&q=1&e=b63ae42f-606a-437e-a926-d47a2107ff19&u=http%3A%2F%2Fwww.tangunsoft.com%2F A (06571) 2F, 67, Seocho-daero, Seocho-gu, Seoul, Republic of Korea

> > > > -----Original Message-----

> > > From: ObjectiveFS <support@objectivefs.com>

> > > Sent: Tuesday, November 25, 2025 2:33 AM

> > > To: 김재희 <jay@tangunsoft.com>

> > > Cc: CS <cs@tangunsoft.com>

> > > Subject: Re: [Tangunsoft] Inquiry Regarding License Usage and Instance Counting for SamsungSDS - ObjectiveFS > > Hi Jay,

> > > > Thank you for your email. We are happy to help the customer on this issue.

> > > > The performance the customer is seeing (10 seconds to create a file) is unusually slow and our engineers are happy to investigate. Could you please provide the following information to help our engineers investigate:

> > > > 1. What type of object store is the customer using (e.g. AWS govcloud, Azure, on-premise, etc)?

> > > > 2. Is the server mounting the filesystem in the same region as the object store?

> > > > 3. What is the latency from the server to the object store? If possible, please provide provide the ping time from the server to the object store (by running "ping <object store endpoint>" from the server).

> > > > 4. What is the performance of the object store (if possible to provide):

> > > a) approximate latency for PUT requests

> > > b) approximate latency for GET requests

> > > c) approximate latency for LIST requests

> > > > 5. Are there are firewall/proxy/scanner between the server and the object store?

> > > > 6. How much RAM is on the server?

> > > > 7. What is the memory cache size (usually specified in /etc/objectivefs.env/CACHESIZE) [if set]?

> > > > 8. Is TLS enabled (i.e. is the endpoint specified with "https://" or /etc/objectivefs.env/TLS set to 1)?

> > > > 9. Is this filesystem mounted on one server or multiple servers?

> > > a) If multiple servers, is the file creation done from one server or multiple servers?

> > > > 10. Can you provide the following information for this filesystem:

> > > a) Size of the filesystem: Output in the "Size" column of "df -h"

> > > b) Number of objects in the bucket: Output of the "IUsed" column of "df -i"

> > > > 11. Version of ObjectiveFS

> > > > 12. Which ObjectiveFS license is the customer using? They currently have two licenses: one Enterprise and one Corporate.

> > > > Other

> > > -----

> > > We understand that the customer cannot share the log file due to the security restrictions.

> > > i) If possible, would it be possible to provide a sample test case so our engineers can try to reproduce this case on our side?

> > > ii) Our engineers are also happy to have a call and screenshare with the customer to investigate case. I have included some suggested times below:

> > > * Nov 25, 2025: 11:30am KST

> > > * Nov 26, 2025: 8am-12pm KST

> > > * Nov 27, 2025: 8am-12pm KST

> > > > > Sincerely,

> > > Sam

> > > > > > >> On Nov 24, 2025, at 1:34 AM, 김재희 <jay@tangunsoft.com> wrote:

> > >> >> Hi, Sam

> > >> >> I hope you are doing well.

> > >> >> We received additional feedback from our customer regarding their new deployment environment, and we would like to ask for your guidance on the matter below.

> > >> >> Our customer is setting up a new environment (not AWS-based), and they are experiencing significant performance issues related to ObjectiveFS. The bottleneck occurs during the “file handler acquisition” step when creating files of various sizes (100K / 200K / 300K / 2MB).

> > >> According to the customer, this process sometimes takes up to 10 seconds or more, which is causing operational concerns.

> > >> >> At the moment, the only information they can access is the /var/log/messages file from the mounted VM. However, the logs only show periodic PUT / GET / CACHE operations, making it very difficult for them to identify the root cause.

> > >> Due to strict security restrictions (the service is related to a government agency), external data transfer is completely prohibited by national policy. Therefore, they are unable to provide additional logs or diagnostic files to you.

> > >> >> Given these limitations, the customer is asking whether there is any possible method to debug or investigate the issue without exporting logs externally.

> > >> >> The currently applied ObjectiveFS mount options are as follows:

> > >> >> auto,_netdev,mtplus,noatime,nodiratime,oob,noratelimit,autofreebw

> > >> >> >> Additionally, DISKCACHE is currently disabled for the purpose of isolating the latency source.

> > >> >> The customer is particularly concerned because ObjectiveFS is being suspected as the cause of the delays, and they would like to rule this out with certainty.

> > >> Any guidance, recommended checks, or internal debugging procedures you can share would be greatly appreciated.

> > >> >> Thank you in advance for your prompt assistance.

> > >> >> >> Best regard,

> > >> >> >> >> Tangunsoft Co., Ltd. / Customer Innovation Team / Manager Jay Kim >> Direct 82.2.6206.2542 / Mobile 010.3967.6206 / Fax 82.2.538.1153 >> E-mail jay@tangunsoft.com / Web https://protect2.fireeye.com/v1/url?k=501c18bf-31970d8f-501d93f0-000babffaa23-8560d43fbd30363b&q=1&e=dc022eaf-cdc1-41b6-9251-e6ec506aee2d&u=http%3A%2F%2Fwww.tangunsoft.com%2F A (06571) >> 2F, 67, Seocho-daero, Seocho-gu, Seoul, Republic of Korea

> > >> >> -----Original Message-----

> > >> From: ObjectiveFS <support@objectivefs.com>

> > >> Sent: Friday, November 21, 2025 12:57 PM

> > >> To: 김재희 <jay@tangunsoft.com>

> > >> Cc: CS <cs@tangunsoft.com>

> > >> Subject: Re: [Tangunsoft] Inquiry Regarding License Usage and Instance >> Counting for SamsungSDS - ObjectiveFS

> > >> >> Hi Jay,

> > >> >> Thank you for your email. I have included the answers to your questions below:

> > >> >> 1. Yes, if four K8S nodes concurrently mount bucket A, it would count as 4 instances.

> > >> >> 2. If bucket B is mounted by the same 4 nodes as the same time as bucket A, it would count as 8 instances.

> > >> >> 3. Yes, the example above (where 4 nodes mount both bucket A and bucket B concurrently) would count as 8 instances.

> > >> >> 4. No, all our plans are based on the number of instances. However, we offer volume discounts for larger deployments.

> > >> >> We offer larger plans with volume discounts (50 instances, 100 instances, 250 instances, etc). Please let us know the approximate number of instances the customer is planning and we are happy to provide a quote for your review.

> > >> >> Sincerely,

> > >> Sam

> > >> >> >> >>> On Nov 20, 2025, at 9:49 PM, 김재희 <jay@tangunsoft.com> wrote:

> > >>> >>> Hi, Team.

> > >>> I hope this message finds you well.

> > >>> This is Jay from Tangunsoft, writing on behalf of our customer SamsungSDS.

> > >>> Based on last year’s quotation, they are currently using the following ObjectiveFS licenses:

> > >>>  • ObjectiveFS Corporate Plan for 1 year (includes 15 instances) — valid from Jan 1, 2025 to Dec 31, 2025

> > >>>  • Additional usage over 15 instances — valid from Jan 1, 2024 to >>> Dec 31, 2024  We would like to clarify the following points regarding their usage environment:

> > >>>  • SamsungSDS uses ObjectiveFS mounted file systems on K8S nodes after creating AWS buckets.

> > >>> For example, if four K8S nodes concurrently mount bucket A, we understand this would consume 4 licenses. Is this correct?

> > >>>  • If an additional bucket (bucket B) is created and mounted by the same 4 nodes, would the license usage remain at 4 instances, or would it increase to 8 instances?

> > >>>  • According to your official documentation (see the screenshot below), it appears that instance counting is based on file systems — which would suggest that in the above example, it may count as 8 licenses. Could you please confirm?

> > >>> <image003.png>

> > >>>  • Lastly, is there any license plan that counts usage based solely on nodes (not the number of file systems mounted)?

> > >>> In other words, if 4 nodes mount both A and B buckets simultaneously, would there be an option to count this scenario as 4 instances only?

> > >>> We would appreciate your clarification on the above points to assist our customer in reviewing their upcoming renewal and potential expansion plans.

> > >>> Thank you in advance for your support.
