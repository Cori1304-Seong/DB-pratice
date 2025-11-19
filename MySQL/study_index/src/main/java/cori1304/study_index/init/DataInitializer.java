package cori1304.study_index.init;

import cori1304.study_index.customer.Customer;
import cori1304.study_index.customer.CustomerRepository;
import cori1304.study_index.order.Order;
import cori1304.study_index.order.OrderRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

@Component
public class DataInitializer implements CommandLineRunner {

    private final CustomerRepository customerRepository;
    private final OrderRepository orderRepository;

    public DataInitializer(CustomerRepository customerRepository,
                           OrderRepository orderRepository) {
        this.customerRepository = customerRepository;
        this.orderRepository = orderRepository;
    }

    @Override
    public void run(String... args) {
        // no-op: data is now initialized via SQL scripts, not Java
    }
}
