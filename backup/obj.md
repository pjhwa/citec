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
