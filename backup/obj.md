Sender : ObjectiveFS <info@objectivefs.com> 

Date : 2025-12-08 08:42 (GMT+9)

Title : Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

To : 이주평<jupyung.lee@samsung.com>

CC : 강유진<yj6.kang@samsung.com>, yjkim@tangunsoft.com<yjkim@tangunsoft.com>, 김은영<ey111.kim@samsung.com>, 이승택<beardsly@samsung.com>, 문상원<sangwon.moon@samsung.com>, 주재민<jm7.joo@samsung.com>, 소운영<wy.so@samsung.com>, 이유선<yousun1.lee@samsung.com>, 손승우<ssw.sohn@samsung.com>, 신동민<dm0501.shin@samsung.com>, 오연재<yeonjae.oh@samsung.com>, 박성일<s-park.park@samsung.com>



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


