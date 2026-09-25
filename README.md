# M321_TBZ_Phaseolus_Express
Phaseolus Central is the meta repo, using Kubernetes to spin up pods with images from the various services, including ones from other repos (ours).

Phaseolus Express

Webapp to order bean food.
Services:
- OrderBeans -> own Repo (Phaseolus_Order)
- PayBeancoins -> own Repo (Phaseolus_Payment)
- CookerBeaners -> own Repo (Phaseolus_Cooker)
- BeanNotifs -> own Repo (Phaseolus_Notifs)
Message Broker: RabbitMQ

Orchestration: Kuberenetes
Clustering: minikube
API Gateway: Traefik
IAM: Keycloack
Metrics: Prometheus and Grafana
CI/CD: Argo CD

