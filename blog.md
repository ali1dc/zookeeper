Zookeeper is an orchestration service, typically associated with distributed systems (think Hadoop or Kafka). Managing Zookeeper, especially in cloud environments can be a difficult and daunting task. In this blog post, I will address the challenge of deploying Zookeeper as a Service on AWS; but first, let's see what Zookeeper is, and why we need it!

## What is Zookeeper
Zookeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services. All of these kinds of services are used in some form or another by distributed applications. Each time they are implemented there is a lot of work that goes into fixing the bugs and race conditions that are inevitable. Because of the difficulty of implementing these kinds of services, applications initially usually skimp on them, which make them brittle in the presence of change and difficult to manage. Even when done correctly, different implementations of these services lead to management complexity when the applications are deployed.

Zookeeper aims at distilling the essence of these different services into a very simple interface to a centralized coordination service. The service itself is distributed and highly reliable. Consensus, group management, and presence protocols will be implemented by the service so that the applications do not need to implement them on their own. Application specific uses of these will consist of a mixture of specific components of Zoo Keeper and application specific conventions.

## Why we need it
#### Controller election
The controller is one of the most important broking entity in a Kafka ecosystem, and it also has the responsibility to maintain the leader-follower relationship across all the partitions. If a node by some reason is shutting down, it’s the controller’s responsibility to tell all the replicas to act as partition leaders in order to fulfill the duties of the partition leaders on the node that is about to fail. So, whenever a node shuts down, a new controller can be elected and it can also be made sure that at any given time, there is only one controller and all the follower nodes have agreed on that.
#### Topics Configuration
The configuration regarding all the topics including the list of existing topics, the number of partitions for each topic, the location of all the replicas, list of configuration overrides for all topics and which node is the preferred leader, etc.
#### ACLs
Access control lists or ACLs for all the topics are also maintained within Zookeeper.
#### Cluster Membership
Zookeeper also maintains a list of all the brokers that are functioning at any given moment and are a part of the cluster.
#### Quotas
How much data is each client allowed to read and write.

**Please note** that Zookeeoer in a mandatory service for running Apache Kafka.

## Challenge with cloud
Provisioning Zookeeper on a cloud service like AWS can be as simple as executing a single command. However, having a fully automated service like Zookeeper after the resources are provisioned in a dynamic cloud environment like AWS is very challenging. 

In a Zookeeper cluster there are number of machines or servers, each one called a `node` and each node needs to know network information (IP or hostname) of other nodes. In addition, other services that use Zookeeper, like Kafka, need to know the Zookeeper IPs hostname. 

Now, let's talk about having Zookeeper cluster on AWS. Imagine we deployed Zookeeper on EC2 instances with Auto Scaling Group - ASG. In that dynamic environment, what happenes if a node got replaced by another one? (Which is very likely to happen.) How do other nodes or other services know a new node's information?

There are several options for addressing that challenge:
1. Using [Consul](https://www.consul.io/discovery.html) service discovery by HashiCorp.
2. Custom node discovery which can be complicated and challenging.
3. Using [Exhibitor](https://github.com/soabase/exhibitor); a Zookeeper node management by Netflix.
4. Zookeeper as a Service (aka Stateless Zookeeper)

We will focus specifically on Zookeeper as a Service, or Stateless Zookeeper.

## What is stateless Zookeeper
Stateless Zookeeper is the configuration and deployment of the Zookeeper cluster, that if a node got terminated, the replacement node get the same node configuration and not will lose any data.
In this section, I will tell you the step by step of how to deploy a stateless Zookeeper cluster in Amazon Web Services, but first let's define some assumptions:
1. We are hosting 3 Zookeeper nodes on `us-east-1` and each node is hosted on one Available Zone (AZ); `us-east-1a`, `us-east-1b` and `us-east-1c`.
2. We are installing Zookeeper on EC2 instances. (each node on an EC2 instance)
3. We are using Auto Scaling Groups - ASG.
4. We have an AMI image with Zookeeper on it. (We are using [Chef](https://www.chef.io/) to bake Zookeeper and all other tools for running it)

### Step 1: Leveraging ENI
We need to create an environment with the static internal IP addresses for the nodes, meaning if a node got replaced, the new one get the same IP address. With Elastic Network Interface - ENI, we can manage ENI attachment in a fairly uncomplicated manner.

In ASG launch configuration, we need to have a script to look for an available ENI in the same AZ and attach it. Here is the ruby example:
```ruby
@ec2 = Aws::EC2::Client.new(region: region)
metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
instance_az = Net::HTTP.get(URI.parse(metadata_endpoint + 'placement/availability-zone'))
# get the available eni
eni = @ec2.describe_network_interfaces(
  filters: [
    { name: 'tag:Name', values: ['ZOOKEEPER-' + '*'] },
    { name: 'availability-zone', values: [instance_az] },
    { name: 'status', values: ['available'] }
  ]).network_interfaces[0]
```
Now we simply can attach the network:
```ruby
metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
instance_id = Net::HTTP.get(URI.parse(metadata_endpoint + 'instance-id'))
eni.attach(instance_id: instance_id, device_index: 1)
```
At this point, we have defined the static IP address and attached it to our EC2 instance, but we are not able to use it for communication yet! First we must create a network config and route, and make our newly attached network device (the ENI) the default. This can be managed by this shell script:
```sh
#!/bin/bash -e
export GATEWAY=`route -n | grep "^0.0.0.0" | tr -s " " | cut -f2 -d" "`

if [ -f /etc/network/interfaces.d/eth1.cfg ]; then mv -f /etc/network/interfaces.d/eth1.cfg /etc/network/interfaces.d/backup.eth1.cfg.backup; fi
cat > /etc/network/interfaces.d/eth1.cfg <<ETHCFG
auto eth1
iface eth1 inet dhcp
    up ip route add default via $GATEWAY dev eth1 table eth1_rt
    up ip rule add from <%= new_ip_address %> lookup eth1_rt prio 1000
ETHCFG

mv /etc/iproute2/rt_tables /etc/iproute2/backup.rt_tables.backup
cat > /etc/iproute2/rt_tables <<RTTABLES
#
# reserved values
#
255     local
254     main
253     default
0       unspec
#
# local
#
#1      inr.ruhep
2 eth1_rt
RTTABLES

ifup eth1

ip route add default via $GATEWAY dev eth1 table eth1_rt;
```

These scripts can be run by Chef in the launch configuration.

### Step 2: Leveraging EBS volume
Now that we have our nodes and ENIs configured, let's consider the issue of data persistence. What happens if a node got terminated or replaced by another one? What is going to happen to the data? What if we lose the data?

Good news: nothing going to happen! Zookeeper is a fault-tolerant and distributed system, means each node has the same data replicated.
Bad news: after each node replacement we may have traffic in our network for replicating data to the new node.
Solution: use an extra EBS volume and set `Delete on termination` property to `false`, and attach to the newly replaced node for storing the Zookeeper data. Here is a python script accomplish this:
```python
conn = ec2.connect_to_region(region_name)

volume = conn.get_all_volumes(
  filters = {
    'tag:Name':tag,
    'availability-zone':instance_az,
    'status':'available'
  })[0]
# attach the volume
conn.attach_volume(volume.id, instance_id, '/dev/xvdg')
# mount it
commands.getstatusoutput('mount /dev/xvdg /var/lib/zookeeper')
```
<!-- ## How to make it Self-Healing -->
## Conclusion
Configuring stateless Zookeeper may have its own challenge, but still, it is easier and less challenging than options mentioned above, and because this is custom code managed and deployed internally, we have more power to make it fit into our organization. In addition, one great characteristic of stateless Zookeeper that has remained hidden so far is Self-Healing Clusters! But, if we follow this pattern with some reasonable improvements available in the source code below, we can easily achieve that. 

[Here](git@github.com:ali1dc/xd-zookeeper.git) you can find the source code for the Zookeeper configuration, ready for AWS deployment.

### References
- https://zookeeper.apache.org/
- https://www.cloudkarafka.com/blog/2018-07-04-cloudkarafka_what_is_zookeeper.html
