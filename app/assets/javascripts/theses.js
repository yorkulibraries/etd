$(document).ready(function () {
	/* FORM */
	$('.select_subjects_fields').chosen({ max_selected_options: 1, allow_single_deselect: true });

	$('#thesis_exam_date').datepicker({ dateFormat: 'yy-mm-dd' });

	/** STATUS NOTIFICATIONS **/
	const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]');
	const popoverList = [...popoverTriggerList].map(popoverTriggerEl => new bootstrap.Popover(popoverTriggerEl, {
		content: $("#status_change").html(),
		html: true,
		sanitize: false,
	}));

	/* ReadOnly Field View */
	$(".readonly-field a").click(function () {
		$(this).parent().hide();
		var show_field = $(this).data("id");
		$("#" + show_field).show();
		return false;
	});


	$(".simple_form").on("click", ".remove_fields", function (event) {
		$(this).prev("input[type=hidden]").val("1");
		$(this).closest("fieldset").remove();
		event.preventDefault();
	});

	$(".simple_form").on("click", ".add_fields", function (event) {
		var time = new Date().getTime();
		var regexp = new RegExp($(this).data("id"), "g");
		$(this).before($(this).data('fields').replace(regexp, time));
		event.preventDefault();

		$(".committee_member_names").autocomplete({
			source: committee_member_names_list
		});
	});

	$('form.file-upload input.file').change ( function() {
	    if ($(this).val()) {
	        $(this).parents('form:first').find('input:submit').removeAttr('disabled');
	    } 
	});
});
