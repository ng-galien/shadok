package com.shadok.pods.quarkus;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
public class HelloWorldResourceTest {

  @Test
  public void testHelloEndpoint() {
    given().when().get("/hello").then().statusCode(200).body(is("Hello World from Quarkus Pod!"));
  }

  @Test
  public void testHelloJsonEndpoint() {
    given()
        .when()
        .get("/hello/json")
        .then()
        .statusCode(200)
        .body("message", is("Hello World from Quarkus Pod!"))
        .body("service", is("quarkus-hello"))
        .body("version", is("1.0.0"));
  }
}
