package cori1304.study_index.order;

import org.springframework.data.jpa.repository.JpaRepository;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByCustomerIdAndOrderDateBetween(
            Long customerId,
            LocalDateTime start,
            LocalDateTime end
    );

    List<Order> findByStatusAndOrderDateBetween(
            String status,
            LocalDateTime start,
            LocalDateTime end
    );

    List<Order> findByTotalAmountGreaterThanEqual(BigDecimal amount);
}
