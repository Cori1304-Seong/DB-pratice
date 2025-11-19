package cori1304.study_index.customer;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface CustomerRepository extends JpaRepository<Customer, Long> {

    Customer findByEmail(String email);

    List<Customer> findByCityAndCreatedAtBetween(
            String city,
            LocalDateTime start,
            LocalDateTime end
    );
}
