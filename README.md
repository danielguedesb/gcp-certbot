# Hello world docker action

Github action that creates/renews a Letsencrypt certificate and, optionally, links it to an existing GCP Load Balancer.

The action will try to obtain a wildcard certificate for the whole domain, *.my.domain , including the domain apex, my.domain.

It will store the certificate in an existing GCP Storage bucket for future reference when renewing the certificate.  

### Requirements

* 1\. Create a new HTTPS Load-balancer [here](https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list)
   * 1\.1\. If you have no HTTPS Front End you'll need a temporary certificate in order to create one. You can use a self signed, or Google managed certificate - The action will update it afterwards.    
* 2\. Create a Cloud DNS Zone [here](https://console.cloud.google.com/net-services/dns)
  * 2\.1\. Name it accordingly, if your domain is _example.com_ then your DNS Zone's DNS Name should be example.com
  * 2\.2\. Setup your registrar to point to the new Google Cloud DNS zone. There is a link in the top right of the console, **'Registrar Setup'**, that has the values you'll need.   
* 3\. Make sure that your service account has, at least, the following roles:

  * resourcemanager.projects.get
  * resourcemanager.projects.list
  * storage.objects.*
  * dns.changes.create
  * dns.changes.get
  * dns.managedZones.list
  * dns.resourceRecordSets.create
  * dns.resourceRecordSets.delete
  * dns.resourceRecordSets.list
  * dns.resourceRecordSets.update

* 3\.1\. If updating a Load Balancer it also needs:

  * compute.forwardingRules.list
  * compute.globalOperations.get
  * compute.sslCertificates.create
  * compute.sslCertificates.get
  * compute.sslCertificates.list
  * compute.targetHttpsProxies.get
  * compute.targetHttpsProxies.list
  * compute.targetHttpsProxies.setSslCertificates

The certificates follow the naming pattern __ZONE-TLD-CERTIFICATE-SERIAL__ where any dots in the domain will be replaced with dashes.
Certificates will never be deleted, just removed from the load-balancer. You can see all certificates in the console [here](https://console.cloud.google.com/net-services/loadbalancing/advanced/sslCertificates/list).

## Inputs

#### `gcp-project`

**Required** Your google cloud project.

#### `gcp-sa`

**Required** The service account that will be used the action.

#### `gcs-bucket`

**Required** Google Cloud Storage bucket where the certificate will be stored.

#### `email`

**Required** The email that will be used when generating your letsencrypt certificates.

#### `domain`

**Required** The plain domain name for which certificates will be generated. The configured zone must match this. The request will be for a certificate that is valid for example.com and *.example.com.

#### `front-end`

**Optional** Load Balancer Front End where the certificate will be attached, leave blank if you don't want this. Default `""`.

#### `tar-password`

**Optional** _(Recommended)_ Password that will be used to protect the tar file uploaded to GCS. Default `""`.

## Outputs

#### `certificate-name`

The name of the created/renewed certificate.

## Example usage

### Creating/Renewing a certificate 

```yaml
name: GCP LetsEncrypt certificate
on:
  workflow_dispatch:
  schedule:
    - cron: '0 1 * * 0' # every week

jobs:
  lets-encrypt:
    runs-on: ubuntu-latest
    steps:
      - uses: danielguedesb/gcp-certbot@v1
      with:
        gcp-project: 'my-project'
        gcp-sa: '${{ secrets.my-project-sa }}'
        gcs-bucket: 'my-project-bucket'
        email: 'my-email@my-domain.com'
        domain: 'my-domain.com'
```
  
### Creating/Renewing a certificate and attaching it to an HTTPS Load Balancer

```yaml
name: GCP LetsEncrypt certificate
on:
  workflow_dispatch:
  schedule:
    - cron: '0 1 * * 0' # every week

jobs:
  lets-encrypt:
    runs-on: ubuntu-latest
    steps:
      - uses: danielguedesb/gcp-certbot@v1
        with:
          gcp-project: 'my-project'
          gcp-sa: '${{ secrets.my-project-sa }}'
          gcs-bucket: 'my-project-bucket'
          email: 'my-email@my-domain.com'
          domain: 'my-domain.com'
          front-end: 'lb-https-frontend-name'
          tar-password: 'my-cert-tar-password'
```
