package com.shadok.pods.quarkus;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello")
public class HelloWorldResource {

  @GET
  @Produces(MediaType.TEXT_PLAIN)
  public String hello() {
    return "Hello World from Quarkus Pod!";
  }

  @GET
  @Path("/json")
  @Produces(MediaType.APPLICATION_JSON)
  public HelloResponse helloJson() {
    return new HelloResponse("Hello World from Quarkus Pod!", "quarkus-hello", "1.0.0");
  }

  public static class HelloResponse {
    public String message;
    public String service;
    public String version;

    public HelloResponse() {}

    public HelloResponse(String message, String service, String version) {
      this.message = message;
      this.service = service;
      this.version = version;
    }
  }
}
