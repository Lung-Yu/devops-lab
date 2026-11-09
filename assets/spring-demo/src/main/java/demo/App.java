package demo;

import jakarta.validation.constraints.NotBlank;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.context.annotation.Bean;
import org.springframework.validation.annotation.Validated;

@SpringBootApplication
@ConfigurationPropertiesScan
public class App {
    private static final Logger log = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) { SpringApplication.run(App.class, args); }

    @Validated
    @ConfigurationProperties(prefix = "app")
    public record AppProperties(@NotBlank String externalApiUrl) {}

    @Bean
    CommandLineRunner demoLog(AppProperties props) {
        return args -> log.atError()
                .addKeyValue("externalApiUrl", props.externalApiUrl())
                .addKeyValue("orderId", 12345)
                .addKeyValue("reason", "payment gateway timeout")
                .log("Order failed");
    }
}
