name 'cookbooks'
maintainer 'Ali Jafari | Excella Data Lab'
maintainer_email 'ali.jafari@excella.com'
license 'All Rights Reserved'
description 'Configures Zookeeper post-install'
long_description 'Installs/Configures cookbooks'
version '0.1.0'
chef_version '>= 12.14' if respond_to?(:chef_version)

# The `issues_url` points to the location where issues for this cookbook are
# tracked.  A `View Issues` link will be displayed on this cookbook's page when
# uploaded to a Supermarket.
#
# issues_url 'https://github.com/<insert_org_here>/cookbooks/issues'

# The `source_url` points to the development repository for this cookbook.  A
# `View Source` link will be displayed on this cookbook's page when uploaded to
# a Supermarket.
#
# source_url 'https://github.com/<insert_org_here>/cookbooks'

# depends 'zookeeper', '~> 10.0.1'

depends 'confluent-cookbook', '~> 0.4.0'
# depends 'confluent-cookbook', '= 0.3.0'
