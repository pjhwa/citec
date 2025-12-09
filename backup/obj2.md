Sender : ObjectiveFS <info@objectivefs.com> 

Date : 2025-12-08 22:19 (GMT+9)

Title : Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

To : 김은영<ey111.kim@samsung.com>

CC : 이주평<jupyung.lee@samsung.com>, 강유진<yj6.kang@samsung.com>, yjkim@tangunsoft.com<yjkim@tangunsoft.com>, 이승택<beardsly@samsung.com>, 문상원<sangwon.moon@samsung.com>, 주재민<jm7.joo@samsung.com>, 소운영<wy.so@samsung.com>, 이유선<yousun1.lee@samsung.com>, 손승우<ssw.sohn@samsung.com>, 신동민<dm0501.shin@samsung.com>, 오연재<yeonjae.oh@samsung.com>, 박성일<s-park.park@samsung.com>, 정기철<kch.jung@samsung.com>, 임부건<ts.lim@samsung.com>, 한호전<hojeon.han@samsung.com>, 최규황<kyuh.choi@samsung.com>, 강재규<jaekyu_kang@samsung.com>



Thank you, Eunyoung. I have confirmed the meeting with my CTO for Dec 12th (Friday) at 9am KST.



We look forward to receiving the zoom link from you.



Sincerely,

Steve



> On Dec 8, 2025, at 8:12 AM, 김은영 <ey111.kim@samsung.com> wrote:

>

> Steve,

>

> Thank you for your quick response.

>

> Here are the answers to your questions:

>

> 1. How many shards does this Ceph RGW bucket have?

> It was 1999, but after the issue reoccurred yesterday, it has now been adjusted to 499.

> And yes, RGW dynamic bucket index resharding is enabled.

>

>

> 2. Among the dates you suggested, December 12th works for us.

> Let’s schedule the meeting at 9:00 AM.

> I will share the Zoom link shortly.

>

>

>

> Thank you again, and looking forward to speaking with you.

>

> Best,

> Eunyoung

>

>

> --------- Original Message ---------

> Sender : ObjectiveFS <info@objectivefs.com>

> Date  : 2025-12-08 21:27 (GMT+9)

> Title : Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

>

> Hi Eunyoung and JP,

>

> Thank you for your emails.

> If all list requests from a mount is blocked for 30 minutes, then that ObjectiveFS mount will not have an up-to-date view of the filesystem and requests from that mount will have to be blocked until ObjectiveFS can get a consistent view of that bucket again.

>

> Blocking for 30 minutes is very uncommon and would normally count as an object store downtime. Would it be possible to check the following for this particular object store:

>        - how many shards does this Ceph RGW have?

>        - Is RGW Dynamic Bucket Index Resharding enabled?

>

> I have included a couple of articles that might be useful:

> - https://www.ibm.com/docs/en/storage-ceph/7.1.0?topic=errors-slow-requests-requests-are-blocked

> - https://protect2.fireeye.com/v1/url?k=4200c5b7-238bd0ae-42014ef8-74fe485cbfec-cc0650d79999b012&q=1&e=240a64c0-3b39-4c8d-96bf-7bea98864f93&u=https%3A%2F%2Fceph.io%2Fen%2Fnews%2Fblog%2F2025%2Fbenchmarking-object-part2%2F

>

> To answer Eunyoung’s questions about the cache setting recommendation: ObjectiveFS will try to keep the cache usage within the CACHESIZE setting. In the case you observed when the CACHESIZE was set to 20%, the RAM usage should be kept at 20% or lower. Increasing the CACHESIZE setting may help cache more frequently used objects in the RAM and reduce the number of Get requests.

>

> We have customers running on many different object stores, including Ceph. However, we do not have visibility into the details in their bucket unless the customers inform us, similar to this case where we need to check with you about the number of objects in this bucket. With the storage layout optimized, we expect to have 1-2 million objects for PB-sized filesystems in a single bucket.

>

> The frequency of list operations can increase if using the “oob” flag. Otherwise, the list operation frequency is not user configurable.

>

> Yes, buckets with more objects can have fewer list operations due to the adaptive logic.

>

> Regarding support escalation, your account currently has basic support with the Enterprise software license plan. The "Premium Support Plan" is required for additional support escalation and higher support level. If you are interested in adding the Premium Support Plan to your account, please let us know.

> We appreciate Samsung as a customer and understand the importance of solving this issue. I am happy to schedule a call with our CTO, Thomas Nordin, to discuss this issue. I have included some availability below:

> * December 9, 2025 (Tuesday): 8:30am KST

> * December 11, 2025 (Thursday): 10am-12pm KST

> * December 12, 2025 (Friday): 9am-11pm KST

>

> Please let me know if any of these times would work for you.

>

> Sincerely,

> Steve

>

> > On Dec 8, 2025, at 5:52 AM, 이주평 <jupyung.lee@samsung.com> wrote:

> > > Hi Steve,

> > > One more follow-up question, what happens to ObjectiveFS if the list API takes Ceph up to 30 minutes? This did happen during the incident. Does it block all pending object requests until the list is finished?

> > > Best,

> > JP

> > --------- Original Message ---------

> > Sender : 김은영 <ey111.kim@samsung.com> 부사장/담당/SCP담당/삼성SDS

> > Date  : 2025-12-08 18:35 (GMT+9)

> > Title : RE: Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

> > > > Hi Steve,

> > > My name is Eunyoung Kim,  EVP at Samsung SDS, leading the Samsung Cloud Platform business unit.

> > > We are facing a critical issue in our Ceph-based object storage environment when ObjectiveFS is used by one of our applications. The incident has affected important public-sector services, so the urgency is very high.

> > > The Ceph bucket involved contains approximately 6 million objects(curretnly in the early stage of the service and expected to grow to tens of millons), and we observe the following symptoms on the Ceph RGW side:

> > > - RGW queue length spikes to over 100

> > - TCP allocation and TCP memory usage increase sharply (from socket statistics)

> > > > One area I would like to ask specifically about is the recommendation to increase the ObjectiveFS cache size.

> > During the incident, ObjectiveFS cache usage never exceeded 20%.

> > Given this, I would like to understand:

> > > > Would increasing the cache size still make a meaningful difference if the existing cache is already under-utilized?

> > Or does the cache affect list behavior in ways that are not reflected in the usage metric?

> > > > > In addition, could you help clarify the following:

> > > 1. Do you have any verified production deployments where ObjectiveFS has been stably used on Ceph object storage with tens of millions of objects in a single bucket?

> > > 2. Is it possible to adjust ObjectiveFS internal behavior, such as:

> > the frequency of list operations, or

> > the number of objects / prefixes evaluated during a list?

> > > 3. From our monitoring, buckets with more objects sometimes produce fewer list operations than buckets with fewer objects.

> > Is this due to ObjectiveFS internal optimization or adaptive logic?

> > > > Given the severity of the impact, we would like to arrange a call with you as soon as possible.

> > Please share your earliest available times, and we will adjust our schedule accordingly.

> > > Lastly, as this issue is directly affecting critical public-sector workloads,

> > please advise us on the appropriate escalation path within ObjectiveFS to ensure we receive the highest level of support.

> > > Thank you very much for your prompt assistance.

> > > >    김 은영 Eunyoung Kim

> >  EVP / SCP Business Unit / Samsung SDS

> > > > > --------- Original Message ---------

> > Sender : ObjectiveFS <info@objectivefs.com> > Date  : 2025-12-08 16:31 (GMT+9)

> > Title  : Re: [urgent] Issues Using ObjectiveFS on SamsungSDS Cloud

> > > Hi JP,

> > > Thank you for your email. Yes, reducing the number of mounts from 8 to 4 will decrease the number of requests to the Ceph bucket. The reason is because each mount issues its own requests to the bucket for the filesystem operations on that particular mount. So, having 8 mounts will have more requests to the bucket. Therefore reducing the number of mounts from 8 to 4 should reduce the amount of requests to the object store.

> > > I highly recommend checking that your filesystem’s storage layout is optimized, especially if there has been a large import of data into the filesystem or the number of objects is 10 million. Having an optimized storage layout can improve the performance, reduce the number of requests to the Ceph cluster and reduce memory usage. > This document has the steps to optimize the storage layout: https://protect2.fireeye.com/v1/url?k=5d5d130b-3cd60612-5d5c9844-74fe485cbfec-e3ffb43942c7d196&q=1&e=240a64c0-3b39-4c8d-96bf-7bea98864f93&u=https%3A%2F%2Fobjectivefs.com%2Fhowto%2Fstorage-layout-performance-optimization

> > > If you have any questions, please feel free to contact us.

> > > Sincerely,

> > Steve

> > > > On Dec 7, 2025, at 8:38 PM, 이주평 <jupyung.lee@samsung.com> wrote:

> > > > Hi Steve,

> > > This ceph bucket was mounted to 8 different clients. As a mitigation, we decreased the number of mounts from 8 to 4, which resolved the performance degradation. As guess about the root cause from this mitigation step?

> > > > Best,

> > > JP
