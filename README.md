# AWS EKS with Terraform

- Infrastructure-as-code project that provisions an Amazon EKS cluster using Terraform.
- Includes Inventory App with two API endpoints to test. EKS auto creates Loadbalancer as part of native managed service.

> [!IMPORTANT]
> **Incurs charges**. Please use `terraform destroy` command when it is not in use.

## Architecture

```
                              AWS Account
                                   |
                                   v
                         +-------------------+
                         |        VPC        |
                         |    10.0.0.0/16    |
                         +-------------------+
                                   |
                    +--------------+--------------+
                    |                             |
                    v                             v
             +-------------+               +-------------+
             |   Public    |               |   Private   |
             |   Subnets   |               |   Subnets   |
             |    AZ-a/b   |               |    AZ-a/b   |
             +-------------+               +-------------+
                    |                             |
                    |                       +-------------+
                    +---------------------->| NAT Gateway |
                                            +-------------+
                                                   |
                                                   v
                                         +-------------------+
                                         |    EKS Cluster    |
                                         |                   |
                                         |  Control Plane    |
                                         |        +          |
                                         |  Managed Nodes    |
                                         +---------+---------+
                                                   |
                                      +------------+------------+
                                      |            |            |
                                      v            v            v
                                  kube-proxy     CoreDNS      VPC CNI
```

### Terraform module structure

```
                         +----------------------+
                         |      Root Module      |
                         |                      |
                         |      main.tf         |
                         +----------+-----------+
                                    |
                       +------------+------------+
                       |                         |
                       v                         v
                +-------------+           +-------------+
                | VPC Module  |           | EKS Module |
                |             |           |             |
                | VPC         |           | EKS Cluster |
                | Subnets     |           | Node Group  |
                | Routing     |           | IAM Roles   |
                | NAT         |           | Add-ons     |
                +-------------+           +-------------+
```

## Repository Structure

```
terraform-eks/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── eks/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── k8s/
    ├── deployment.yaml
    └── service.yaml
```

### Module responsibilities

**VPC module**

- VPC
- Public and private subnets
- Internet Gateway
- NAT Gateway
- Route tables
- Routing configuration

**EKS module**

- EKS cluster
- EKS cluster IAM role
- Managed node group
- Node IAM role
- EKS add-ons

This separation keeps networking and Kubernetes infrastructure independently organized.

## Prerequisites

The following tools are required:

- AWS CLI
- Terraform
- kubectl
- AWS credentials with permissions to provision the required infrastructure

Verify AWS authentication:

```
aws sts get-caller-identity
```

Format and initialize Terraform:

```
terraform fmt -recursive
terraform init
```

Review the planned infrastructure:

```
terraform plan
```

Apply the infrastructure:

```
terraform apply
```

View Terraform outputs:

```
terraform output
```

List resources currently tracked by Terraform:

```
terraform state list
```

  ## Configure kubectl

After the EKS cluster has been created, configure the local kubeconfig:

```
aws eks update-kubeconfig \
  --region <aws-region> \
  --name <cluster-name>
```

Verify access to the cluster:

```
kubectl get nodes
```

Example:

```
NAME                                       STATUS   ROLES    AGE
ip-10-0-11-18.eu-west-2.compute.internal   Ready    <none>   6m
```

Check the Kubernetes namespaces:

```
kubectl get namespaces
```

Check the EKS system components:

```
kubectl get pods -n kube-system
```

The cluster should have system components such as:

- AWS VPC CNI
- CoreDNS
- kube-proxy

## Deploy the Application

The Kubernetes manifests are stored in the `k8s/` directory.

Apply them with:

```
kubectl apply -f k8s/
```

Check the application pods:

```
kubectl get pods
```

Check the Kubernetes Services:
> The application Service is configured as a `LoadBalancer`, which causes the AWS integration to provision the required load-balancing  infrastructure. The external endpoint can be retrieved with:
```
kubectl get svc
```

## Verify the Application

Once the application pod is running and the external load balancer is available, test the application using its external endpoint.

### Inventory endpoint

```
curl http://<load-balancer-endpoint>/inventory
```

Example response:

```
[
  {
    "id": 1,
    "name": "RS Runner Shoes",
    "stock": 42,
    "price": 59.99
  }
]
```

### Health endpoint

```
curl http://<load-balancer-endpoint>/actuator/health
```

Expected response:

```
{
  "status": "UP"
}
```

## Troubleshooting

### Pod stuck in `Pending`

If a pod remains in `Pending`, inspect the pod events:

```
kubectl describe pod <pod-name>
```

The scheduler events can identify why the pod cannot be placed on a node.

For example:

```
0/1 nodes are available: 1 Too many pods.
```

This indicates that the node has reached its pod capacity.

Inspect the node:

```
kubectl describe node <node-name>
```

Look at the node's capacity and currently allocated pods:

```
Capacity:
  pods: 4

Non-terminated Pods:
  ...
```

In EKS, the maximum number of pods a node can support is affected by the underlying EC2 instance and the networking configuration, including the AWS VPC CNI.

If a node has insufficient pod capacity, possible solutions include:

- Using a larger EC2 instance type.
- Adding additional nodes to the managed node group.
- Configuring the node group with appropriate scaling settings.
- Reviewing pod resource and scheduling requirements.

## Infrastructure Ownership

Terraform manages the AWS infrastructure defined by the project, including the VPC and EKS resources.

Kubernetes manages resources deployed inside the cluster, such as:

- Deployments
- Pods
- Services
- ConfigMaps
- Other Kubernetes objects

A Kubernetes `Service` of type `LoadBalancer` can cause AWS load-balancing infrastructure to be provisioned dynamically by the Kubernetes/AWS integration.

Therefore, not every AWS resource visible in the AWS console is necessarily a Terraform-managed resource.

The ownership boundary should be intentional when combining Terraform and Kubernetes.

## EKS Add-ons

EKS add-ons are explicitly managed through Terraform in this project.

Although EKS can provide and manage certain cluster components automatically, defining them through Terraform makes their configuration and lifecycle part of the infrastructure code.

This provides:

- Reproducible infrastructure
- Visibility of managed components
- Consistent configuration
- Infrastructure lifecycle management through Terraform

## IAM and Kubernetes RBAC

AWS IAM and Kubernetes RBAC control different layers of access.

**AWS IAM**

Controls who or what can access AWS APIs and infrastructure.

**Kubernetes RBAC**

Controls permissions for resources inside the Kubernetes cluster.

The Terraform execution identity should have the AWS permissions required to provision the infrastructure, while application users and developers should receive only the permissions required for their respective responsibilities.

## Design Decisions

### Separate VPC and EKS modules

Networking and Kubernetes infrastructure are separated into dedicated Terraform modules.

This makes the infrastructure easier to understand, maintain, and reuse.

### Private worker nodes

The EKS worker nodes are placed in private subnets.

Outbound internet access can be provided through the NAT Gateway when required, while the nodes themselves do not need to be directly exposed to the public internet.

### Managed node group

The project uses an EKS managed node group so that AWS manages several aspects of the underlying worker-node lifecycle.

Terraform remains responsible for the desired configuration of the node group.

### Kubernetes LoadBalancer Service

The application is exposed using a Kubernetes `Service` with type `LoadBalancer`.

This allows the Kubernetes/AWS integration to provision the required external load-balancing infrastructure rather than manually configuring an external endpoint for the application.

## Useful Commands

### Terraform

```
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply
terraform output
terraform state list
```

### Kubernetes

```
kubectl get nodes
kubectl get namespaces
kubectl get pods
kubectl get pods -n kube-system
kubectl get svc
kubectl describe pod <pod-name>
kubectl describe node <node-name>
```

### AWS / EKS

```
aws sts get-caller-identity

aws eks update-kubeconfig \
  --region <aws-region> \
  --name <cluster-name>
```

## Cleanup

To delete the deployed app:
```
kubectl delete -f k8s/
```

To remove the infrastructure managed by Terraform:
```
terraform destroy
```

Review the resources that will be removed before confirming the operation.