# M321_TBZ_Phaseolus_Express
Phaseolus Central is the meta repo, using Kubernetes to spin up pods with images from the various services, including ones from other repos (ours).

Phaseolus Express

Webapp to order bean food.
Services:
- [BeanApp]()
- [OrderBeans](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Order)
- [PayBeancoins](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Pay)
- [CookerBeaners](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Cooker)
- [BeanNotifs](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Notifs)
- Message Broker: RabbitMQ

Orchestration: Kuberenetes
Clustering: minikube
API Gateway: Traefik
IAM: Keycloack
Metrics: Prometheus and Grafana
CI/CD: Argo CD

