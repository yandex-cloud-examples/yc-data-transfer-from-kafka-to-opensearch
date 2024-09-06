# Infrastructure for the Yandex Cloud Managed Service for Apache Kafka®, Managed Service for OpenSearch, and Data Transfer
#
# RU: https://cloud.yandex.ru/docs/data-transfer/tutorials/mkf-to-mos
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/mkf-to-mos
#
# Specify the following settings:
locals {
  # Source Managed Service for Apache Kafka® cluster settings:
  kf_version       = "" # Set a desired version of Apache Kafka®. For available versions, see the documentation main page: https://cloud.yandex.com/en/docs/managed-kafka/
  kf_user_password = "" # Set a password for the Apache Kafka® user

  # Source Managed Service for OpenSearch cluster settings:
  os_version       = "" # Set a desired version of OpenSearch. For available versions, see the documentation main page: https://cloud.yandex.com/en/docs/managed-opensearch/
  os_user_password = "" # Set a password for the OpenSearch user

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  source_endpoint_id = "" # Set the source endpoint ID
  target_endpoint_id = "" # Set the target endpoint ID
  transfer_enabled   = 0  # Set to 1 to enable Transfer

  # The following settings are predefined. Change them only if necessary.
  network_name          = "network"            # Name of the network
  subnet_name           = "subnet-a"           # Name of the subnet
  zone_a_v4_cidr_blocks = "10.1.0.0/16"        # CIDR block for the subnet in the ru-central1-a availability zone
  security_group_name   = "security-group"     # Name of the security group
  kf_cluster_name       = "kafka-cluster"      # Name of the Apache Kafka® cluster
  kf_username           = "mkf-user"           # Name of the Apache Kafka® username
  kf_topic              = "sensor"             # Name of the Apache Kafka® topic
  os_cluster_name       = "opensearch-cluster" # Name of the OpenSearch cluster
}

# Network infrastructure

resource "yandex_vpc_network" "network" {
  description = "Network for the Managed Service for Apache Kafka® and Managed Service for OpenSearch clusters"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_security_group" "clusters-security-group" {
  description = "Security group for the Managed Service for Apache Kafka and Managed Service for OpenSearch clusters"
  name        = local.security_group_name
  network_id  = yandex_vpc_network.network.id

  ingress {
    description    = "Allow connections to the Managed Service for Apache Kafka® cluster from the Internet"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for OpenSearch cluster from the Internet with Dashboards"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for OpenSearch cluster from the Internet"
    protocol       = "TCP"
    port           = 9200
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "The rule allows all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "kafka-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  name               = local.kf_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.clusters-security-group.id]

  config {
    brokers_count    = 1
    version          = local.kf_version
    zones            = ["ru-central1-a"]
    assign_public_ip = true # Required for connection from the Internet
    kafka {
      resources {
        resource_preset_id = "s2.micro" # 2 vCPU, 8 GB RAM
        disk_type_id       = "network-hdd"
        disk_size          = 10 # GB
      }
    }
  }
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "mkf-user" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.kf_username
  password   = local.kf_user_password
  permission {
    topic_name = "sensors"
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = "sensors"
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "sensors" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-cluster.id
  name               = local.kf_topic
  partitions         = 2
  replication_factor = 1
}

# Infrastructure for the Managed Service for OpenSearch cluster

resource "yandex_mdb_opensearch_cluster" "opensearch_cluster" {
  description        = "Managed Service for OpenSearch cluster"
  name               = local.os_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.clusters-security-group.id]

  config {

    version        = local.os_version
    admin_password = local.os_user_password

    opensearch {
      node_groups {
        name             = "opensearch-group"
        assign_public_ip = true
        hosts_count      = 1
        zone_ids         = ["ru-central1-a"]
        subnet_ids       = [yandex_vpc_subnet.subnet-a.id]
        roles            = ["DATA", "MANAGER"]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }

    dashboards {
      node_groups {
        name             = "dashboards-group"
        assign_public_ip = true
        hosts_count      = 1
        zone_ids         = ["ru-central1-a"]
        subnet_ids       = [yandex_vpc_subnet.subnet-a.id]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }

  }

  maintenance_window {
    type = "ANYTIME"
  }

  depends_on = [
    yandex_vpc_subnet.subnet-a
  ]
}

# Data Transfer infrastructure

resource "yandex_datatransfer_transfer" "mkf-mos-transfer" {
  count       = local.transfer_enabled
  description = "Transfer from the Managed Service for Apache Kafka® to the Managed Service for OpenSearch"
  name        = "transfer-from-mkf-to-mos"
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "INCREMENT_ONLY" # Replication data
}
