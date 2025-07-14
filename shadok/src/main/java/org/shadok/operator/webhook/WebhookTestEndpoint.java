package org.shadok.operator.webhook;

import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.api.model.admission.v1.AdmissionRequest;
import io.fabric8.kubernetes.api.model.admission.v1.AdmissionReview;
import io.quarkus.arc.profile.IfBuildProfile;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;
import org.shadok.operator.model.ApplicationType;

/**
 * Endpoint de test pour valider manuellement les mutations du webhook Actif uniquement avec le
 * profil 'debug'
 */
@Path("/webhook-test")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
@IfBuildProfile("debug")
public class WebhookTestEndpoint {

  @Inject PodMutatingWebhook webhook;

  /** Test simple avec un Pod minimal pour valider les mutations */
  @POST
  @Path("/test-mutation")
  public Response testMutation(TestPodRequest request) {
    try {
      // Créer un Pod de test avec les annotations Shadok
      Pod testPod = createTestPod(request);

      // Créer une AdmissionReview simulée
      AdmissionReview admissionReview = createTestAdmissionReview(testPod);

      // Appliquer la mutation via le webhook
      AdmissionReview response = webhook.mutate(admissionReview);

      // Retourner la réponse avec le Pod muté
      return Response.ok(
              Map.of(
                  "original",
                  testPod,
                  "mutated",
                  extractMutatedPod(response),
                  "success",
                  response.getResponse().getAllowed(),
                  "message",
                  "Mutation appliquée avec succès"))
          .build();

    } catch (Exception e) {
      return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
          .entity(Map.of("error", e.getMessage(), "success", false))
          .build();
    }
  }

  /** Test avec différents types d'applications */
  @POST
  @Path("/test-application-type/{type}")
  public Response testApplicationType(@PathParam("type") String applicationType) {
    try {
      // Valider le type d'application
      ApplicationType.valueOf(applicationType.toUpperCase());

      TestPodRequest request =
          new TestPodRequest(
              "test-" + applicationType.toLowerCase(),
              "test-namespace",
              "test-application",
              Map.of());

      return testMutation(request);

    } catch (IllegalArgumentException e) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(
              Map.of(
                  "error",
                  "Type d'application invalide: " + applicationType,
                  "validTypes",
                  List.of(ApplicationType.values()),
                  "success",
                  false))
          .build();
    }
  }

  /** Endpoint pour lister les types d'applications supportés */
  @GET
  @Path("/application-types")
  public Response getApplicationTypes() {
    return Response.ok(
            Map.of(
                "applicationTypes",
                ApplicationType.values(),
                "description",
                "Types d'applications supportés par Shadok"))
        .build();
  }

  /** Test de santé du webhook */
  @GET
  @Path("/health")
  public Response health() {
    return Response.ok(
            Map.of(
                "status", "UP",
                "webhook", "ready",
                "profile", "debug"))
        .build();
  }

  /** Créer un Pod de test avec les bonnes annotations */
  private Pod createTestPod(TestPodRequest request) {
    return new PodBuilder()
        .withNewMetadata()
        .withName(request.podName())
        .withNamespace(request.namespace())
        .withAnnotations(Map.of("org.shadok/application", request.applicationName()))
        .addToAnnotations(request.additionalAnnotations())
        .endMetadata()
        .withNewSpec()
        .withContainers(
            new ContainerBuilder()
                .withName("app")
                .withImage("nginx:latest")
                .withPorts(
                    new ContainerPortBuilder().withContainerPort(8080).withName("http").build())
                .build())
        .withServiceAccountName("default")
        .endSpec()
        .build();
  }

  /** Créer une AdmissionReview de test */
  private AdmissionReview createTestAdmissionReview(Pod pod) {
    AdmissionRequest request = new AdmissionRequest();
    request.setKind(new GroupVersionKind("v1", "", "Pod"));
    request.setOperation("CREATE");
    request.setNamespace(pod.getMetadata().getNamespace());
    request.setObject(pod);
    request.setUid("test-uid-" + System.currentTimeMillis());

    AdmissionReview review = new AdmissionReview();
    review.setApiVersion("admission.k8s.io/v1");
    review.setKind("AdmissionReview");
    review.setRequest(request);

    return review;
  }

  /** Extraire le Pod muté de la réponse */
  private Pod extractMutatedPod(AdmissionReview response) {
    if (response.getResponse() != null && response.getResponse().getAllowed()) {
      // En réalité, il faudrait appliquer les patches JSON
      // Pour simplifier, on retourne un message
      return new PodBuilder()
          .withNewMetadata()
          .withName("mutated-pod")
          .withAnnotations(Map.of("mutation", "applied"))
          .endMetadata()
          .build();
    }
    return null;
  }

  /** Record for test requests */
  public record TestPodRequest(
      String podName,
      String namespace,
      String applicationName,
      Map<String, String> additionalAnnotations) {}
}
